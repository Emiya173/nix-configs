module Xlog.Internal.Key (PrivateKey (..)) where

import Data.ByteString (ByteString)

-- The constructor is private to the package; public construction validates it.
newtype PrivateKey = PrivateKey ByteString

instance Show PrivateKey where
  show _ = "<private key>"
