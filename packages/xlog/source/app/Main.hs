module Main (main) where

import Control.Concurrent (forkFinally, setNumCapabilities, newEmptyMVar, newMVar, putMVar, takeMVar, modifyMVar)
import Control.Exception (IOException, SomeException, bracketOnError, catch, displayException, throwIO)
import Control.Monad (forM, replicateM, unless, when)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.ByteString.Lazy as LBS
import Data.Char (isSpace)
import Data.List (dropWhileEnd, sort)
import GHC.Conc (getNumProcessors)
import System.Console.GetOpt
import System.Directory
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.FilePath
import System.IO
import Text.Read (readMaybe)
import Xlog

data Flag = KeyFile FilePath | StrictFlag | Jobs String | MaxOutput String | Help

flags :: [OptDescr Flag]
flags =
  [ Option [] ["private-key-file"] (ReqArg KeyFile "FILE") "64 hexadecimal digits (surrounding whitespace allowed)"
  , Option [] ["strict"] (NoArg StrictFlag) "fail on the first malformed record"
  , Option ['j'] ["jobs"] (ReqArg Jobs "N") "directory worker count (default: available logical CPUs)"
  , Option [] ["max-output"] (ReqArg MaxOutput "BYTES") "total output limit per file (default 1 GiB)"
  , Option ['h'] ["help"] (NoArg Help) "show usage"
  ]

usage :: String
usage = usageInfo "Usage: xlog-hs [OPTIONS] [INPUT [OUTPUT]]\nWithout INPUT, decode *.xlog in the current directory.\nFor a file, OUTPUT defaults to INPUT.log; directories are non-recursive.\nDefault key: $XDG_CONFIG_HOME/xlog/private.key (usually ~/.config/xlog/private.key)." flags

main :: IO ()
main = run `catch` \(err :: IOException) -> die (displayException err)

run :: IO ()
run = do
  args <- getArgs
  let (opts, paths, errors) = getOpt Permute flags args
  unless (null errors) (die (concat errors ++ usage))
  if any isHelp opts then putStr usage else do
    processors <- max 1 <$> getNumProcessors
    (options, jobs) <- configure processors opts
    files <- resolvePaths paths
    let workers = min jobs (length files)
    -- Enable CPU parallelism as well as file concurrency, without allocating
    -- idle capabilities when there are fewer files than CPUs or requested jobs.
    setNumCapabilities (max 1 (min processors workers))
    results <- pooled workers (decodeFile options) files
    unless (and results) exitFailure
  where
    isHelp Help = True
    isHelp _ = False

configure :: Int -> [Flag] -> IO (DecodeOptions, Int)
configure processors opts = do
  (options, jobs) <- go defaultDecodeOptions processors False opts
  case privateKey options of
    Just _ -> pure (options, jobs)
    Nothing -> do
      path <- getXdgDirectory XdgConfig ("xlog" </> "private.key")
      exists <- doesFileExist path
      if exists then do
        key <- readPrivateKey path
        pure (options { privateKey = Just key }, jobs)
      else pure (options, jobs)
  where
    go options jobs _ [] = pure (options, jobs)
    go options jobs hasKey (flag : rest) = case flag of
      Help -> go options jobs hasKey rest
      StrictFlag -> go options { recovery = Strict } jobs hasKey rest
      Jobs value -> positive "jobs" value >>= \n -> go options n hasKey rest
      MaxOutput value -> positive "max-output" value >>= \n -> go options { maxTotalOutputBytes = n } jobs hasKey rest
      KeyFile path -> do
        when hasKey (die "Specify --private-key-file only once")
        key <- readPrivateKey path
        go options { privateKey = Just key } jobs True rest
    positive label value = case readMaybe value of
      Just n | n > 0 -> pure n
      _ -> die ("Invalid " ++ label ++ ": expected a positive integer")

readPrivateKey :: FilePath -> IO PrivateKey
readPrivateKey path = do
  raw <- BSC.readFile path
  let text = dropWhileEnd isSpace (dropWhile isSpace (BSC.unpack raw))
  either (const (die "Invalid private key: expected a secp256k1 scalar as 64 hex digits")) pure (parsePrivateKey text)

resolvePaths :: [FilePath] -> IO [(FilePath, FilePath)]
resolvePaths [] = resolvePaths ["."]
resolvePaths [input] = do
  directory <- doesDirectoryExist input
  if directory then do
    names <- sort <$> listDirectory input
    candidates <- forM (filter ((== ".xlog") . takeExtension) names) $ \name -> do
      let path = input </> name
      regular <- doesFileExist path
      pure [ (path, path ++ ".log") | regular ]
    pure (concat candidates)
  else do
    exists <- doesFileExist input
    unless exists (die ("Input file does not exist: " ++ input))
    pure [(input, input ++ ".log")]
resolvePaths [input, output] = do
  regular <- doesFileExist input
  unless regular (die "With OUTPUT specified, INPUT must be a regular file")
  pure [(input, output)]
resolvePaths _ = die usage

decodeFile :: DecodeOptions -> (FilePath, FilePath) -> IO Bool
decodeFile options (input, output) = action `catch` \(err :: IOException) -> do
  hPutStrLn stderr (input ++ ": " ++ displayException err)
  pure False
  where
    action = do
      source <- canonicalizePath input
      target <- canonicalizePath output
      when (source == target) (ioError (userError "Input and output must be different files"))
      bytes <- BS.readFile input
      result <- decodeXlog options bytes
      case result of
        Left err -> hPutStrLn stderr (input ++ ": " ++ show err) >> pure False
        Right report -> do
          atomicWrite output (decodedBytes report)
          mapM_ (hPutStrLn stderr . ((input ++ ": ") ++) . show) (diagnostics report)
          putStrLn (input ++ " -> " ++ output ++ " (" ++ show (decodedRecords report) ++ " records)")
          pure True

-- Decode fully before replacing the destination. Temporary files live alongside
-- it so rename is atomic on the target filesystem, and are removed on failure.
atomicWrite :: FilePath -> LBS.ByteString -> IO ()
atomicWrite output bytes = bracketOnError
  (openBinaryTempFile (takeDirectory output) (takeFileName output ++ ".tmp"))
  (\(path, handle) -> ignoreIO (hClose handle) >> ignoreIO (removeFile path))
  (\(path, handle) -> LBS.hPut handle bytes >> hClose handle >> renameFile path output)

ignoreIO :: IO () -> IO ()
ignoreIO action = action `catch` \(_ :: IOException) -> pure ()

-- A fixed number of workers consumes an immutable list through one MVar.
-- There is no thread per file; forkFinally guarantees every worker signals exit.
pooled :: Int -> (a -> IO Bool) -> [a] -> IO [Bool]
pooled count action items = do
  queue <- newMVar items
  completions <- replicateM (min count (length items)) newEmptyMVar
  let worker !ok = do
        next <- modifyMVar queue $ \remaining -> case remaining of
          [] -> pure ([], Nothing)
          x : xs -> pure (xs, Just x)
        case next of
          Nothing -> pure ok
          Just x -> action x >>= \success -> worker (ok && success)
  mapM_ (forkFinally (worker True) . putMVar) completions
  outcomes <- mapM takeMVar completions
  mapM (either throwIO pure) (outcomes :: [Either SomeException Bool])

die :: String -> IO a
die message = hPutStrLn stderr message >> exitFailure
