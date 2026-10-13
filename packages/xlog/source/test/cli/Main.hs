module Main (main) where

import Control.Monad (forM_, void)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.List (isInfixOf)
import System.Directory
import System.Exit (ExitCode (..))
import System.Environment (getEnvironment)
import System.FilePath ((</>))
import System.Process (CreateProcess (cwd, env), proc, readCreateProcessWithExitCode)
import System.Timeout (timeout)
import Test.Support
import Test.Temp (withTempDirectory)

-- Cabal puts the executable declared in build-tool-depends on the test PATH.
-- Each case owns its workspace and can fail without contaminating another case.
main :: IO ()
main = do
  environment <- getEnvironment
  executable <- findExecutable "xlog-hs" >>= maybe
    (ioError (userError "xlog-hs not on PATH; run this suite with cabal test")) makeAbsolute
  fixtures <- makeAbsolute "test/fixtures"
  original <- BS.readFile (fixtures </> "type-08.xlog")
  expected <- BS.readFile (fixtures </> "type-08.golden")
  combined <- BS.readFile (fixtures </> "all.golden")
  let sample work = work </> "sample.xlog"
      output work = work </> "output.log"
      encrypted = fixtures </> "all.xlog"
      key = fixtures </> "test-private-key.txt"
      sentinel = BSC.pack "existing output must survive"
      inWorkspace action = withTempDirectory "xlog-hs-cli-" $ \work -> do
        BS.writeFile (sample work) original
        action work
      command work ok args = do
        let isolated = ("XDG_CONFIG_HOME", work </> "config") : filter ((/= "XDG_CONFIG_HOME") . fst) environment
        result <- timeout 30000000 (readCreateProcessWithExitCode
          (proc executable args) { cwd = Just work, env = Just isolated } "")
        case result of
          Nothing -> ioError (userError ("CLI timed out: " ++ show args))
          Just (code, stdoutText, stderrText) -> do
            assert ("unexpected exit " ++ show code ++ " for " ++ show args ++ "\n" ++ stdoutText ++ stderrText)
              ((code == ExitSuccess) == ok)
            pure stderrText
      succeeds work = void . command work True
      fails work = void . command work False
      contents path bytes = BS.readFile path >>= equal bytes
      absent path = doesPathExist path >>= assert ("unexpected file: " ++ path) . not
      preserves work args = do
        BS.writeFile (output work) sentinel
        fails work args
        contents (output work) sentinel
      broken work = do
        let path = work </> "broken.xlog"
        BS.writeFile path (BS.pack [255,255] <> original <> BS.singleton 254)
        pure path
      test name action = (name, inWorkspace action)
  runTests $
    [ test "help" $ \work -> succeeds work ["--help"]
    , test "default file output" $ \work -> do
        succeeds work [sample work]
        contents (sample work ++ ".log") expected
    , test "explicit output" $ \work -> do
        succeeds work [sample work, output work]
        contents (output work) expected
    , test "reject input as output" $ \work -> do
        fails work [sample work, sample work]
        contents (sample work) original
    , test "reject symlink to input" $ \work -> do
        createFileLink (sample work) (output work)
        fails work [sample work, output work]
        contents (sample work) original
    , test "encrypted mixed stream" $ \work -> do
        succeeds work ["--private-key-file", key, encrypted, output work]
        contents (output work) combined
    , test "missing key preserves output" $ \work -> preserves work [encrypted, output work]
    , test "default XDG private key" $ \work -> do
        let config = work </> "config" </> "xlog"
        createDirectoryIfMissing True config
        copyFile key (config </> "private.key")
        succeeds work [encrypted, output work]
        contents (output work) combined
    , test "explicit key overrides default key" $ \work -> do
        let config = work </> "config" </> "xlog"
        createDirectoryIfMissing True config
        writeFile (config </> "private.key") "invalid default key"
        succeeds work ["--private-key-file", key, encrypted, output work]
        contents (output work) combined
    , test "invalid default key fails without disclosure" $ \work -> do
        let config = work </> "config" </> "xlog"
        createDirectoryIfMissing True config
        writeFile (config </> "private.key") (replicate 64 'g')
        stderrText <- command work False [encrypted, output work]
        assert "default key leaked" (not (replicate 64 'g' `isInfixOf` stderrText))
        absent (output work)
    , test "output limit preserves output" $ \work ->
        preserves work ["--max-output", "2", sample work, output work]
    , test "recovery diagnostics stay out of output" $ \work -> do
        path <- broken work
        stderrText <- command work True [path]
        assert "missing recovery diagnostic" ("SkippedBytes" `isInfixOf` stderrText)
        contents (path ++ ".log") expected
    , test "strict failure preserves output" $ \work -> do
        path <- broken work
        preserves work ["--strict", path, output work]
    , test "parallel directory selection is non-recursive" $ \work -> do
        createDirectory (work </> "nested")
        BS.writeFile (work </> "nested" </> "nested.xlog") original
        BS.writeFile (work </> "ignored.txt") original
        BS.writeFile (work </> "second.xlog") original
        succeeds work ["--jobs", "2", work]
        contents (sample work ++ ".log") expected
        contents (work </> "second.xlog.log") expected
        absent (work </> "nested" </> "nested.xlog.log")
        absent (work </> "ignored.txt.log")
    , test "default current directory" $ \work -> do
        succeeds work []
        contents (sample work ++ ".log") expected
    , test "automatic workers decode every file" $ \work -> do
        let inputs = [work </> ("auto-" ++ show n ++ ".xlog") | n <- [1..32 :: Int]]
        forM_ inputs $ \path -> BS.writeFile path original
        succeeds work [work]
        forM_ (sample work : inputs) $ \path -> contents (path ++ ".log") expected
    , test "empty directory with automatic workers" $ \work -> do
        let empty = work </> "empty"
        createDirectory empty
        succeeds work [empty]
        listDirectory empty >>= equal []
    , test "batch failure still decodes other files" $ \work -> do
        BS.writeFile (work </> "failure.xlog") (BSC.pack "garbage")
        fails work ["-j", "3", work]
        absent (work </> "failure.xlog.log")
        contents (sample work ++ ".log") expected
    ] ++
    [ test ("reject invalid arguments " ++ show args) $ \work -> fails work args
    | args <- [["--jobs", "0"], ["--jobs", "x"], ["--max-output", "-1"],
               ["--unknown"], ["missing"], ["a", "b", "c"]]
    ] ++
    [ test "invalid key is redacted" $ \work -> do
        let badKey = work </> "bad.key"
        writeFile badKey (replicate 64 'g')
        stderrText <- command work False ["--private-key-file", badKey, sample work]
        assert "private key leaked" (not (replicate 64 'g' `isInfixOf` stderrText))
    , test "write failure removes temporary files" $ \work -> do
        createDirectory (output work)
        fails work [sample work, output work]
        names <- listDirectory work
        forM_ names $ \name -> assert ("temporary output leaked: " ++ name) (not (".tmp" `isInfixOf` name))
    , test "empty input produces empty output" $ \work -> do
        BS.writeFile (sample work) BS.empty
        succeeds work [sample work]
        contents (sample work ++ ".log") BS.empty
    ]
