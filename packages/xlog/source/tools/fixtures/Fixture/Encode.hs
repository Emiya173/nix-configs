-- Independent encoder for synthetic test data. No production Xlog imports.
module Fixture.Encode (generateFixtures, teaEncryptWith) where

import Control.Monad (forM, unless)
import Data.Binary.Put (Put, putByteString, putWord8, putWord16le, putWord32le, runPut)
import Data.Bits (shiftL, shiftR, xor, (.|.))
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import Data.Text.Encoding (encodeUtf8)
import Data.Word (Word8, Word16, Word32)
import Fixture.Compression

-- Only fixed, public test points are used. This arithmetic is not suitable for
-- processing real private keys and is not linked into the decoder library.
prime :: Integer
prime = 2 ^ (256 :: Int) - 2 ^ (32 :: Int) - 977

generator :: (Integer, Integer)
generator =
  ( 0x79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798
  , 0x483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8 )

powMod :: Integer -> Integer -> Integer
powMod base powerValue = go base powerValue 1
  where
    go _ 0 !acc = acc
    go !value !power !acc = go (value * value `mod` prime) (power `div` 2)
      (if odd power then acc * value `mod` prime else acc)

doublePoint :: (Integer, Integer) -> (Integer, Integer)
doublePoint (x, y) = (nextX, (slope * (x - nextX) - y) `mod` prime)
  where
    slope = 3 * x * x * powMod (2 * y) (prime - 2) `mod` prime
    nextX = (slope * slope - 2 * x) `mod` prime

integerBytes :: Integer -> BS.ByteString
integerBytes n = BS.pack [fromInteger (n `shiftR` bit) | bit <- [248,240..0]]

publicKey :: BS.ByteString
publicKey = let (x, y) = doublePoint generator in integerBytes x <> integerBytes y

sharedSecret :: BS.ByteString
sharedSecret = BS.take 32 publicKey -- Test server scalar 1, client scalar 2.

bytes :: Put -> BS.ByteString
bytes = LBS.toStrict . runPut

wordLE :: BS.ByteString -> Word32
wordLE = BS.foldr (\byte acc -> fromIntegral byte .|. (acc `shiftL` 8)) 0 . BS.take 4

teaEncrypt :: BS.ByteString -> BS.ByteString
teaEncrypt = teaEncryptWith sharedSecret

-- Test/benchmark helper. The caller supplies the ECDH bytes; the decoder does
-- not depend on this independent encryption implementation.
teaEncryptWith :: BS.ByteString -> BS.ByteString -> BS.ByteString
teaEncryptWith secret = bytes . blocks
  where
    k0 = wordLE secret
    k1 = wordLE (BS.drop 4 secret)
    k2 = wordLE (BS.drop 8 secret)
    k3 = wordLE (BS.drop 12 secret)
    blocks input
      | BS.length input < 8 = putByteString input
      | otherwise = do
          let (a, b) = rounds (16 :: Int) 0 (wordLE input) (wordLE (BS.drop 4 input))
          putWord32le a
          putWord32le b
          blocks (BS.drop 8 input)
    rounds 0 _ !a !b = (a, b)
    rounds n !total !a !b =
      let total' = total + 0x9e3779b9
          a' = a + (((b `shiftL` 4) + k0) `xor` (b + total') `xor` ((b `shiftR` 5) + k1))
          b' = b + (((a' `shiftL` 4) + k2) `xor` (a' + total') `xor` ((a' `shiftR` 5) + k3))
      in rounds (n - 1) total' a' b'

envelope :: Word8 -> Word16 -> BS.ByteString -> BS.ByteString
envelope magic seqNo payload = bytes $ do
  putWord8 magic
  unless (magic <= 2) (putWord16le seqNo >> putWord8 8 >> putWord8 9)
  putWord32le (fromIntegral (BS.length payload))
  unless (magic < 6) (putByteString publicKey)
  putByteString payload
  putWord8 0

frame :: Word8 -> Word16 -> BS.ByteString -> IO BS.ByteString
frame magic seqNo input = do
  compressed <- if magic `elem` [2,4,5,7,9] then compress DeflateFlushed input
    else if magic `elem` [12,13] then compress ZstdFrame input
    else pure input
  let payload
        | magic <= 5 =
            let len = BS.length compressed + if magic == 5 then 4 else 0
                key = 0xcc `xor` magic `xor` (if magic <= 2 then fromIntegral len else fromIntegral seqNo)
                encrypted = BS.map (`xor` key) compressed
                (first, second) = BS.splitAt (BS.length encrypted `div` 2) encrypted
                chunk part = putWord16le (fromIntegral (BS.length part)) >> putByteString part
            in if magic == 5 then bytes (chunk first >> chunk second) else encrypted
        | magic `elem` [7,12] = teaEncrypt compressed
        | otherwise = compressed
  pure (envelope magic seqNo payload)

pad :: Int -> String
pad n = if n < 10 then '0' : show n else show n

generateFixtures :: IO [(FilePath, BS.ByteString)]
generateFixtures = do
  records <- forM [1..13] $ \magic -> do
    let message = encodeUtf8 (Text.pack ("record " ++ pad magic ++ ": 你好 Haskell\n")) <> BS.pack [0,255,13,10]
    encoded <- frame (fromIntegral magic) (fromIntegral magic) message
    pure (magic, encoded, message)
  finished <- compress DeflateFinished (BSC.pack "finished\n")
  flushed <- compress ZstdFlushed (BSC.pack "flushed\n")
  one <- compress ZstdFrame (BSC.pack "one\n")
  two <- compress ZstdFrame (BSC.pack "two\n")
  large <- forM [9,13] $ \magic -> do
    encoded <- frame magic 1 (BS.replicate 262144 65)
    pure ("large-" ++ show magic ++ ".xlog", encoded)
  pure $
    [ ("test-private-key.txt", BSC.pack (replicate 63 '0' ++ "1\n"))
    , ("peer-public.bin", publicKey)
    , ("shared-secret.bin", sharedSecret)
    , ("shared-secret-double.bin", integerBytes (fst (doublePoint (doublePoint generator))))
    , ("all.xlog", BS.concat [encoded | (_, encoded, _) <- records])
    , ("all.golden", BS.concat [message | (_, _, message) <- records])
    , ("deflate-finished.xlog", envelope 9 1 finished)
    , ("zstd-flushed.xlog", envelope 13 1 flushed)
    , ("zstd-concatenated.xlog", envelope 13 1 (one <> two))
    ] ++ concat
    [ [("type-" ++ pad magic ++ ".xlog", encoded), ("type-" ++ pad magic ++ ".golden", message)]
    | (magic, encoded, message) <- records
    ] ++ large ++
    [ ("tea-" ++ pad len ++ ".bin", teaEncrypt (BS.pack (take len [0..]))) | len <- [0..23] ]
