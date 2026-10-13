module Main (main) where

import Control.Exception (IOException, catch, displayException)
import Control.Monad (forM_, unless)
import qualified Data.ByteString as BS
import Data.List (sort)
import Fixture.Encode (generateFixtures)
import System.Directory (createDirectoryIfMissing, listDirectory)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.FilePath ((</>))
import System.IO (hPutStrLn, stderr)

main :: IO ()
main = run `catch` \(err :: IOException) -> hPutStrLn stderr (displayException err) >> exitFailure

run :: IO ()
run = do
  args <- getArgs
  case args of
    ["--check", directory] -> do
      fixtures <- generateFixtures
      names <- listDirectory directory
      unless (sort names == sort (map fst fixtures)) (fail "Fixture inventory differs")
      forM_ fixtures $ \(name, expected) -> do
        actual <- BS.readFile (directory </> name)
        unless (actual == expected) (fail ("Fixture bytes differ: " ++ name))
      putStrLn ("Verified " ++ show (length fixtures) ++ " fixtures byte for byte")
    ["--help"] -> putStrLn usage
    [directory] -> do
      fixtures <- generateFixtures
      createDirectoryIfMissing True directory
      forM_ fixtures $ \(name, content) -> BS.writeFile (directory </> name) content
      putStrLn ("Generated " ++ show (length fixtures) ++ " fixtures in " ++ directory)
    _ -> hPutStrLn stderr usage >> exitFailure
  where
    usage = "Usage: generate-fixtures OUTPUT_DIRECTORY\n       generate-fixtures --check FIXTURE_DIRECTORY"
