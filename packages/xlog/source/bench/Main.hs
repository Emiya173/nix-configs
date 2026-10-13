module Main (main) where

import Bench.Corpus
import Bench.Report
import Control.Exception (IOException, catch, displayException)
import Control.Monad (forM, forM_, unless, when)
import qualified Data.ByteString as BS
import Data.Char (isSpace)
import Data.List (dropWhileEnd)
import Data.Maybe (fromMaybe)
import Data.Time (defaultTimeLocale, formatTime, getCurrentTime)
import GHC.Clock (getMonotonicTimeNSec)
import GHC.Conc (getNumProcessors)
import System.Console.GetOpt
import System.Directory
import System.Environment (getArgs, getEnvironment)
import System.Exit (ExitCode (..), exitFailure)
import System.FilePath ((</>))
import System.Info (arch, os)
import System.IO (BufferMode (LineBuffering), hPutStrLn, hSetBuffering, stderr, stdout)
import System.Process (CreateProcess (env), proc, readCreateProcessWithExitCode)
import System.Timeout (timeout)
import Test.Temp (withTempDirectory)
import Text.Printf (printf)
import Text.Read (readMaybe)
import Xlog (PrivateKey, parsePrivateKey)

data Options = Options
  { baselinePath :: Maybe FilePath, candidatePath :: Maybe FilePath
  , pythonScript :: Maybe FilePath, pythonPath :: Maybe FilePath
  , keyPath :: Maybe FilePath, outputPath :: Maybe FilePath
  , rounds :: Int, warmups :: Int, files :: Int, records :: Int, recordBytes :: Int
  }

defaults :: Options
defaults = Options Nothing Nothing Nothing Nothing Nothing Nothing 5 1 32 128 16384

type Update = Options -> Either String Options

flags :: [OptDescr Update]
flags =
  [ Option [] ["baseline"] (ReqArg (\p o -> Right o { baselinePath = Just p }) "PATH") "old C++ executable (required)"
  , Option [] ["candidate"] (ReqArg (\p o -> Right o { candidatePath = Just p }) "PATH") "Haskell executable (default: Cabal-built xlog-hs)"
  , Option [] ["python-script"] (ReqArg (\p o -> Right o { pythonScript = Just p }) "PATH") "optional Python decoder to include unchanged"
  , Option [] ["python"] (ReqArg (\p o -> Right o { pythonPath = Just p }) "PATH") "Python interpreter (default: python2 on PATH)"
  , Option [] ["key-file"] (ReqArg (\p o -> Right o { keyPath = Just p }) "PATH") "legacy key (default: XDG xlog/private.key)"
  , Option [] ["output"] (ReqArg (\p o -> Right o { outputPath = Just p }) "DIR") "new report directory (default: bench/results/TIMESTAMP)"
  , numeric "rounds" "measured rounds per engine (default 5)" (\n o -> o { rounds = n })
  , numeric "warmups" "warmup rounds per engine (default 1)" (\n o -> o { warmups = n })
  , numeric "files" "files per directory case (default 32)" (\n o -> o { files = n })
  , numeric "records" "records per file (default 128)" (\n o -> o { records = n })
  , numeric "record-bytes" "decoded bytes per record (default 16384)" (\n o -> o { recordBytes = n })
  ]
  where
    numeric name description setter = Option [] [name] (ReqArg (\value options ->
      case readMaybe value of
        Just n | n > 0 -> Right (setter n options)
        _ -> Left ("--" ++ name ++ " requires a positive integer")) "N") description

usage :: String
usage = usageInfo "Usage: cabal bench migration-bench --benchmark-options='--baseline OLD_XLOG [OPTIONS]'\nUse --help to show this message." flags

main :: IO ()
main = action `catch` \(err :: IOException) -> hPutStrLn stderr (displayException err) >> exitFailure
  where
    action = do
      hSetBuffering stdout LineBuffering
      args <- getArgs
      if "--help" `elem` args then putStr usage else do
        let (updates, extra, errors) = getOpt Permute flags args
        unless (null errors && null extra) (fail (concat errors ++ usage))
        options <- either fail pure (foldl (\acc update -> acc >>= update) (Right defaults) updates)
        run options

run :: Options -> IO ()
run options = do
  old <- maybe (fail "--baseline OLD_XLOG is required") executable (baselinePath options)
  new <- maybe (findExecutable "xlog-hs" >>= maybe (fail "Cannot locate xlog-hs; use --candidate") executable)
    executable (candidatePath options)
  when (old == new) (fail "Baseline and candidate must be different executables")
  python <- case pythonScript options of
    Nothing -> do
      when (pythonPath options /= Nothing) (fail "--python requires --python-script")
      pure Nothing
    Just path -> do
      script <- executable path
      interpreter <- maybe
        (findExecutable "python2" >>= maybe (fail "Cannot locate python2; use --python") executable)
        executable (pythonPath options)
      (code, out, err) <- readCreateProcessWithExitCode (proc interpreter ["--version"]) ""
      unless (code == ExitSuccess) (fail "Cannot query Python interpreter version")
      pure (Just (interpreter, script, unwords (words (out ++ err))))
  defaultKey <- getXdgDirectory XdgConfig ("xlog" </> "private.key")
  keyFile <- makeAbsolute (fromMaybe defaultKey (keyPath options))
  key <- readKey keyFile
  -- Stay within the production decoder's documented per-file/record limits.
  when (recordBytes options > 64 * 1024 * 1024
        || toInteger (records options) * toInteger (recordBytes options) > 1024 * 1024 * 1024)
    (fail "Requested corpus exceeds the default decoder limits")
  now <- getCurrentTime
  let stamp = formatTime defaultTimeLocale "%Y%m%d-%H%M%S" now
  output <- makeAbsolute (fromMaybe ("bench/results" </> stamp) (outputPath options))
  exists <- doesPathExist output
  when exists (fail "Report directory already exists; choose a new --output directory")
  cores <- getNumProcessors
  oldIdentity <- identity old
  newIdentity <- identity new
  pythonMetadata <- case python of
    Nothing -> pure []
    Just (interpreter, script, version) -> do
      scriptIdentity <- identity script
      pure ["- Python script: " ++ scriptIdentity,
        "- Python interpreter: `" ++ interpreter ++ "` (" ++ version ++ ")",
        "- Python arguments: -B SCRIPT INPUT; script and its directory execution policy are unchanged"]
  temporary <- getTemporaryDirectory
  let metadata =
        [ "- UTC: " ++ show now
        , "- Platform: " ++ os ++ "/" ++ arch ++ "; available logical CPUs: " ++ show cores
        , "- Baseline: " ++ oldIdentity
        , "- Candidate: " ++ newIdentity
        , "- Measured rounds per engine: " ++ show (rounds options) ++ "; warmups per engine: " ++ show (warmups options)
        , "- Directory files: " ++ show (files options) ++ "; records per file: " ++ show (records options)
          ++ "; decoded bytes per record: " ++ show (recordBytes options)
        , "- Corpus parent directory: " ++ temporary ++ " (temporary data removed after completion)"
        , "- Candidate arguments: --private-key-file KEY_FILE INPUT; default automatic workers, no explicit --jobs"
        , "- Baseline arguments: INPUT; original directory worker policy unchanged"
        , "- GHCRTS is removed from child environments; binaries are not rebuilt or modified by this benchmark."
        ] ++ pythonMetadata
      engines = [Baseline, Candidate] ++ [Python | Just _ <- [python]]
      command scenario engine = case engine of
        Baseline -> pure (old, [scenarioInput scenario])
        Candidate -> pure (new, ["--private-key-file", keyFile, scenarioInput scenario])
        Python -> case python of
          Just (interpreter, script, _) -> pure (interpreter, ["-B", script, scenarioInput scenario])
          Nothing -> fail "Python runner is not configured"
  createDirectoryIfMissing True output
  environment <- filter ((/= "GHCRTS") . fst) <$> getEnvironment
  withTempDirectory "xlog-migration-bench-" $ \root -> do
    putStrLn "Generating deterministic corpus (not timed)..."
    scenarios <- makeCorpus root key (files options) (records options) (recordBytes options)
    let one scenario engine = do
          -- Both engines create fresh output paths; neither gets an existing
          -- destination from the other engine. Preserve input files throughout.
          forM_ (scenarioFiles scenario) $ \(input, _) -> do
            let path = input ++ ".log"
            present <- doesFileExist path
            when present (removeFile path)
          (program, arguments) <- command scenario engine
          start <- getMonotonicTimeNSec
          result <- timeout (300 * 1000000) $ readCreateProcessWithExitCode
            (proc program arguments) { env = Just environment } ""
          end <- getMonotonicTimeNSec
          case result of
            Nothing -> fail (show engine ++ " exceeded 300 seconds")
            Just (code, _, errors) -> unless (code == ExitSuccess)
              (fail (show engine ++ " failed: " ++ show code ++ " " ++ errors))
          forM_ (scenarioFiles scenario) $ \(input, expected) -> do
            decoded <- BS.readFile (input ++ ".log")
            unless (decoded == expected) (fail (show engine ++ " produced incorrect output for " ++ scenarioName scenario))
          pure (fromIntegral (end - start) / 1e9 :: Double)
        measure scenario = do
          putStrLn ("Warming and validating " ++ scenarioName scenario ++ "...")
          forM_ [1..warmups options] $ \_ -> mapM_ (one scenario) engines
          concat <$> forM [1..rounds options] (\roundNo -> do
            let offset = (roundNo - 1) `mod` length engines
                order = drop offset engines ++ take offset engines
            forM order $ \engine -> do
              seconds <- one scenario engine
              printf "%s round %d %s: %.3f ms\n" (scenarioName scenario) roundNo (show engine) (seconds * 1000)
              pure (Sample (scenarioName scenario) engine roundNo seconds))
        loop completed samples [] = do
          let report = renderReport metadata completed samples
          putStrLn report
          putStrLn ("Reports: " ++ output)
        loop completed samples (scenario : rest) = do
          fresh <- measure scenario
          let completed' = completed ++ [scenario]
              samples' = samples ++ fresh
          writeFile (output </> "samples.csv") (renderCsv completed' samples')
          writeFile (output </> "report.md") (renderReport metadata completed' samples')
          loop completed' samples' rest
    loop [] [] scenarios
  where
    executable path = do
      absolute <- canonicalizePath path
      regular <- doesFileExist absolute
      unless regular (fail ("Executable does not exist: " ++ path))
      pure absolute
    identity path = do
      size <- getFileSize path
      modified <- getModificationTime path
      pure ("`" ++ path ++ "` (" ++ show size ++ " bytes, modified " ++ show modified ++ ")")

readKey :: FilePath -> IO PrivateKey
readKey path = do
  raw <- readFile path
  let text = dropWhileEnd isSpace (dropWhile isSpace raw)
  either (const (fail "Invalid benchmark private key")) pure (parsePrivateKey text)
