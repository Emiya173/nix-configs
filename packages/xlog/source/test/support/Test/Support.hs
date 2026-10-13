module Test.Support (assert, equal, right, runTests) where

import Control.Exception (SomeException, displayException, try)
import Control.Monad (forM, unless)
import System.Exit (exitFailure)

assert :: String -> Bool -> IO ()
assert message ok = unless ok (ioError (userError message))

equal :: (Eq a, Show a) => a -> a -> IO ()
equal expected actual = assert ("expected " ++ show expected ++ ", got " ++ show actual) (expected == actual)

right :: Show e => Either e a -> IO a
right = either (ioError . userError . show) pure

runTests :: [(String, IO ())] -> IO ()
runTests tests = do
  successes <- forM tests $ \(name, action) -> do
    result <- try action
    case result of
      Left (err :: SomeException) -> putStrLn ("FAIL " ++ name ++ ": " ++ displayException err) >> pure False
      Right () -> putStrLn ("PASS " ++ name) >> pure True
  putStrLn (show (length (filter id successes)) ++ "/" ++ show (length tests) ++ " test groups passed")
  unless (and successes) exitFailure
