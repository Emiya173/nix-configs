{-# LANGUAGE ForeignFunctionInterface #-}
module Xlog.Native (nativeBackend) where

import Control.Exception (bracket, mask_)
import qualified Data.ByteString as BS
import Foreign (Ptr, alloca, allocaBytes, castPtr, nullPtr, peek, poke)
import Foreign.C.Types (CInt (..), CSize (..))
import Foreign.Marshal.Alloc (free)
import Xlog.Decode (Backend (..))
import Xlog.Internal.Key (PrivateKey (..))
import Xlog.Types

foreign import ccall safe "xlog_decompress"
  c_decompress :: CInt -> Ptr a -> CSize -> CSize -> Ptr (Ptr b) -> Ptr CSize -> IO CInt

foreign import ccall safe "xlog_shared_secret"
  c_sharedSecret :: Ptr a -> Ptr b -> Ptr c -> IO CInt

nativeBackend :: Backend IO
nativeBackend = Backend decompressNative deriveSecret

decompressNative :: Compression -> Int -> BS.ByteString -> IO (Either ErrorKind BS.ByteString)
decompressNative codec limit input
  | limit < 0 = pure (Left OutputLimitExceeded)
  | otherwise = BS.useAsCStringLen input $ \(src, len) ->
      alloca $ \out -> alloca $ \outLen -> mask_ $ do
        poke out nullPtr
        status <- c_decompress (case codec of RawDeflate -> 0; Zstd -> 1)
          src (fromIntegral len) (fromIntegral limit) out outLen
        case status of
          0 -> bracket (peek out) free $ \buffer -> do
            size <- peek outLen
            Right <$> BS.packCStringLen (castPtr buffer, fromIntegral size)
          2 -> pure (Left OutputLimitExceeded)
          3 -> pure (Left (NativeFailure "native allocation failed"))
          _ -> pure (Left (NativeFailure (show codec ++ ": invalid or incomplete compressed data")))

deriveSecret :: PrivateKey -> BS.ByteString -> IO (Either ErrorKind BS.ByteString)
deriveSecret (PrivateKey key) public
  | BS.length public /= 64 = pure (Left InvalidPublicKey)
  | otherwise = BS.useAsCString key $ \secret -> BS.useAsCString public $ \peer ->
      allocaBytes 32 $ \out -> do
        status <- c_sharedSecret secret peer out
        case status of
          0 -> Right <$> BS.packCStringLen (castPtr out, 32)
          1 -> pure (Left InvalidPublicKey)
          _ -> pure (Left (NativeFailure "ECDH shared secret derivation failed"))
