module Xlog.Crypto (parsePrivateKey, TeaKey, teaKeyFromBytes, teaDecrypt, xorPayload) where

import Data.Binary.Get (getWord32le, runGetOrFail)
import Data.Bits (shiftL, shiftR, xor)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.ByteString.Builder (byteString, toLazyByteString, word32LE)
import qualified Data.ByteString.Lazy as LBS
import Data.Char (digitToInt, isHexDigit)
import Data.Word (Word8, Word32)
import Xlog.Internal.Key (PrivateKey (..))
import Xlog.Types (ErrorKind (..))

parsePrivateKey :: String -> Either ErrorKind PrivateKey
parsePrivateKey text
  | length text /= 64 || not (all isHexDigit text) = Left InvalidPrivateKey
  | BS.all (== 0) bytes || bytes >= curveOrder = Left InvalidPrivateKey
  | otherwise = Right (PrivateKey bytes)
  where
    bytes = BS.pack (pairs text)
    pairs (a : b : rest) = fromIntegral (digitToInt a * 16 + digitToInt b) : pairs rest
    pairs _ = []
    curveOrder = BS.pack (pairs "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141")

data TeaKey = TeaKey !Word32 !Word32 !Word32 !Word32

teaKeyFromBytes :: ByteString -> Either ErrorKind TeaKey
teaKeyFromBytes bytes
  | BS.length bytes /= 16 = Left InvalidTeaKey
  | otherwise = case runGetOrFail parser (LBS.fromStrict bytes) of
      Left _ -> Left InvalidTeaKey
      Right (_, _, key) -> Right key
  where
    parser = TeaKey <$> getWord32le <*> getWord32le <*> getWord32le <*> getWord32le

xorPayload :: Word8 -> ByteString -> ByteString
xorPayload key = BS.map (`xor` key)

-- | Mars uses 16 TEA rounds, LE words, and leaves the final 0..7 bytes intact.
teaDecrypt :: TeaKey -> ByteString -> ByteString
teaDecrypt (TeaKey k0 k1 k2 k3) = LBS.toStrict . toLazyByteString . go
  where
    go bytes
      | BS.length bytes < 8 = byteString bytes
      | otherwise = case runGetOrFail ((,) <$> getWord32le <*> getWord32le) (LBS.fromStrict bytes) of
          Left _ -> byteString bytes -- Unreachable after the length check.
          Right (_, _, (v0, v1)) ->
            let (a, b) = rounds (16 :: Int) 0xe3779b90 v0 v1
            in word32LE a <> word32LE b <> go (BS.drop 8 bytes)
    rounds 0 _ !a !b = (a, b)
    rounds n !total !a !b =
      let b' = b - (((a `shiftL` 4) + k2) `xor` (a + total) `xor` ((a `shiftR` 5) + k3))
          a' = a - (((b' `shiftL` 4) + k0) `xor` (b' + total) `xor` ((b' `shiftR` 5) + k1))
      in rounds (n - 1) (total - 0x9e3779b9) a' b'
