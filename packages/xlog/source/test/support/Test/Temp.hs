module Test.Temp (withTempDirectory) where

import Control.Exception (IOException, bracket, bracketOnError, catch)
import System.Directory (createDirectory, getTemporaryDirectory, removeDirectoryRecursive, removeFile)
import System.IO (hClose, openBinaryTempFile)

-- Keep a uniquely created reservation file until the directory is released.
withTempDirectory :: String -> (FilePath -> IO a) -> IO a
withTempDirectory prefix action = bracket acquire release (action . snd)
  where
    acquire = do
      root <- getTemporaryDirectory
      bracketOnError (openBinaryTempFile root prefix)
        (\(path, handle) -> ignoreIO (hClose handle) >> removeFile path)
        (\(path, handle) -> do
          hClose handle
          let directory = path ++ ".dir"
          createDirectory directory
          pure (path, directory))
    release (path, directory) = removeDirectoryRecursive directory >> removeFile path
    ignoreIO action' = action' `catch` \(_ :: IOException) -> pure ()
