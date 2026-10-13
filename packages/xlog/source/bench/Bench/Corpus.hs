module Bench.Corpus (Scenario (..), makeCorpus) where

import Control.Monad (forM)
import Data.Binary.Put
import Data.Bits (shiftR, xor)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.ByteString.Lazy as LBS
import Data.Word (Word8, Word64)
import Fixture.Compression
import Fixture.Encode (teaEncryptWith)
import Numeric (showHex)
import System.Directory (createDirectory, getFileSize)
import System.FilePath ((</>))
import Xlog (PrivateKey, Backend (..), nativeBackend)

data Scenario = Scenario
  { scenarioName :: !String
  , scenarioInput :: !FilePath
  , scenarioFiles :: ![(FilePath, BS.ByteString)]
  , encodedBytes :: !Integer
  , plainBytes :: !Integer
  }

-- Deterministic log-shaped data: repeated fields plus varying request IDs.
-- It is synthetic, and intentionally not an all-zero compression benchmark.
payload :: Int -> Int -> BS.ByteString
payload size recordIndex = BS.take size $ BS.concat
  [ BSC.pack ("2026-09-05T12:00:00.000Z INFO worker=decode record=" ++ show recordIndex
      ++ " request=" ++ hex (mix n) ++ hex (mix (n + 17))
      ++ " span=" ++ hex (mix (n + 39)) ++ " status=200 latency_us=" ++ show (mix n `mod` 100000)
      ++ " component=xlog message=decoded-a-log-record\n")
  | n <- take (size `div` 100 + 1) [fromIntegral recordIndex * 100003 ..]
  ]
  where
    mix :: Word64 -> Word64
    mix x = let a = (x `xor` (x `shiftR` 30)) * 0xbf58476d1ce4e5b9
                b = (a `xor` (a `shiftR` 27)) * 0x94d049bb133111eb
            in b `xor` (b `shiftR` 31)
    hex value = let text = showHex value "" in replicate (16 - length text) '0' ++ text

-- The peer is the public point 2G. ECDH is derived once during untimed setup;
-- each decoder still performs its own ECDH for every encrypted record.
peerPublic :: BS.ByteString
peerPublic = BS.pack (bytes x ++ bytes y)
  where
    x = 0xc6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5 :: Integer
    y = 0x1ae168fea63dc339a3c58419466ceaeef7f632653266d0e1236431a950cfe52a :: Integer
    bytes n = [fromInteger (n `shiftR` bit) | bit <- [248,240..0]]

envelope :: Word8 -> Int -> BS.ByteString -> BS.ByteString
envelope magic sequenceNo body = LBS.toStrict $ runPut $ do
  putWord8 magic
  -- Keep a valid sequence even for corpus sizes beyond the Word16 range.
  putWord16le (fromIntegral (1 + (sequenceNo - 1) `mod` 65535))
  putWord8 12
  putWord8 12
  putWord32le (fromIntegral (BS.length body))
  putByteString peerPublic
  putByteString body
  putWord8 0

makeCorpus :: FilePath -> PrivateKey -> Int -> Int -> Int -> IO [Scenario]
makeCorpus root key fileCount recordCount recordSize = do
  secret <- sharedSecret nativeBackend key peerPublic >>= either (fail . show) pure
  variants <- forM [("deflate", DeflateFlushed, 9, 7), ("zstd", ZstdFrame, 13, 12)] $
    \(label, codec, plainMagic, encryptedMagic) -> do
      records <- forM [1..recordCount] $ \n -> do
        let text = payload recordSize n
        compressed <- compress codec text
        pure (text, envelope plainMagic n compressed, envelope encryptedMagic n (teaEncryptWith secret compressed))
      let plain = BS.concat [text | (text, _, _) <- records]
          clear = BS.concat [body | (_, body, _) <- records]
          encrypted = BS.concat [body | (_, _, body) <- records]
      pure (label, clear, encrypted, plain)
  singles <- forM variants $ \(label, clear, encrypted, plain) -> do
    a <- writeScenario ("single-" ++ label) False [(clear, plain)]
    b <- writeScenario ("single-encrypted-" ++ label) False [(encrypted, plain)]
    pure [a, b]
  clearBatch <- writeScenario "directory-mixed" True
    (take fileCount (cycle [(clear, plain) | (_, clear, _, plain) <- variants]))
  encryptedBatch <- writeScenario "directory-encrypted-mixed" True
    (take fileCount (cycle [(encrypted, plain) | (_, _, encrypted, plain) <- variants]))
  pure (concat singles ++ [clearBatch, encryptedBatch])
  where
    writeScenario name directory records = do
      let path = root </> name
      createDirectory path
      files <- forM (zip [1 :: Int ..] records) $ \(i, (input, expected)) -> do
        let file = path </> ("file-" ++ show i ++ ".xlog")
        BS.writeFile file input
        pure (file, expected)
      inputBytes <- sum <$> mapM (getFileSize . fst) files
      let outputBytes = sum [toInteger (BS.length expected) | (_, expected) <- files]
      case files of
        (first, _) : _ -> pure (Scenario name (if directory then path else first) files inputBytes outputBytes)
        [] -> fail "Empty benchmark corpus"
