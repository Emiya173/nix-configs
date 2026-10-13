module Xlog
  ( module Xlog.Types, parsePrivateKey, decodeXlog, decodeXlogWith, Backend (..), nativeBackend
  ) where

import Data.ByteString (ByteString)
import Xlog.Crypto (parsePrivateKey)
import Xlog.Decode
import Xlog.Native (nativeBackend)
import Xlog.Types

decodeXlog :: DecodeOptions -> ByteString -> IO (Either DecodeError DecodeReport)
decodeXlog = decodeXlogWith nativeBackend
