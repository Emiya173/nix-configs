module Main (main) where

import Control.Monad (forM_, unless)
import Data.Binary.Put (putByteString, putWord8, putWord16le, putWord32le, runPut)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.ByteString.Lazy as LBS
import Data.Functor.Identity (Identity (..))
import Data.Word (Word8, Word16, Word32)
import Test.Support
import Xlog
import Xlog.Crypto
import Xlog.Format

fixture :: String -> IO BS.ByteString
fixture name = BS.readFile ("test/fixtures/" ++ name)

pad :: Int -> String
pad n = if n < 10 then '0' : show n else show n

record :: Word8 -> Word16 -> BS.ByteString -> BS.ByteString
record magic seqNo payload = LBS.toStrict $ runPut $ do
  putWord8 magic
  unless (magic <= 2) (putWord16le seqNo >> putWord8 8 >> putWord8 9)
  putWord32le (fromIntegral (BS.length payload))
  unless (magic < 6) (putByteString (BS.replicate 64 0))
  putByteString payload
  putWord8 0

plain :: Word16 -> String -> BS.ByteString
plain seqNo = record 8 seqNo . BSC.pack

strict :: DecodeOptions
strict = defaultDecodeOptions { recovery = Strict }

expectKind :: ErrorKind -> IO (Either DecodeError DecodeReport) -> IO ()
expectKind kind action = action >>= \result -> case result of
  Left err -> equal kind (errorKind err)
  Right _ -> ioError (userError ("expected failure " ++ show kind))

main :: IO ()
main = do
  key <- right (parsePrivateKey (replicate 63 '0' ++ "1"))
  let options = strict { privateKey = Just key }
      decode options' bytes = decodeXlog options' bytes >>= right
      golden name expected = fixture name >>= decode options >>= equal expected . LBS.toStrict . decodedBytes
      tests =
        [ ("all 13 format goldens", forM_ [1..13] $ \n -> do
            bytes <- fixture ("type-" ++ pad n ++ ".xlog")
            expected <- fixture ("type-" ++ pad n ++ ".golden")
            report <- decode options bytes
            equal expected (LBS.toStrict (decodedBytes report))
            equal 1 (decodedRecords report)
            equal [] (diagnostics report))
        , ("mixed stream", do
            bytes <- fixture "all.xlog"
            expected <- fixture "all.golden"
            report <- decode options bytes
            equal expected (LBS.toStrict (decodedBytes report))
            equal 13 (decodedRecords report)
            equal [] (diagnostics report))
        , ("independent ECDH vector", do
            peer <- fixture "peer-public.bin"
            expected <- fixture "shared-secret.bin"
            actual <- sharedSecret nativeBackend key peer >>= right
            equal expected actual)
        , ("ECDH boundary scalars", do
            peer <- fixture "peer-public.bin"
            forM_ [
              ("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140", "shared-secret.bin"),
              ("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd036413f", "shared-secret-double.bin"),
              (replicate 63 '0' ++ "2", "shared-secret-double.bin")
              ] $ \(hex, name) -> do
                scalar <- right (parsePrivateKey hex)
                expected <- fixture name
                actual <- sharedSecret nativeBackend scalar peer >>= right
                equal expected actual)
        , ("TEA blocks and every tail length", do
            secret <- fixture "shared-secret.bin"
            teaKey <- right (teaKeyFromBytes (BS.take 16 secret))
            forM_ [0..23] $ \n -> do
              encrypted <- fixture ("tea-" ++ pad n ++ ".bin")
              equal (BS.pack (take n [0..])) (teaDecrypt teaKey encrypted))
        , ("key validation and redaction", do
            equal "<private key>" (show key)
            forM_ ["", replicate 64 '0', replicate 64 'g', replicate 63 '1',
                   "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141",
                   replicate 64 'f'] $ \text -> case parsePrivateKey text of
              Left InvalidPrivateKey -> pure ()
              _ -> assert "accepted invalid key" False)
        , ("invalid TEA key", case teaKeyFromBytes BS.empty of
            Left InvalidTeaKey -> pure ()
            _ -> assert "accepted invalid TEA key" False)
        , ("missing private key", fixture "type-07.xlog" >>= expectKind MissingPrivateKey . decodeXlog strict)
        , ("invalid curve point", expectKind InvalidPublicKey (decodeXlog options (record 7 1 (BSC.pack "12345678"))))
        , ("empty file", decode strict BS.empty >>= equal (DecodeReport LBS.empty 0 []))
        , ("empty records", forM_ [1..13] $ \magic -> do
            let bytes = record magic 0 BS.empty
            (_, next) <- right (parseFrame 1000 0 bytes)
            equal (BS.length bytes) next)
        , ("finished raw DEFLATE", golden "deflate-finished.xlog" (BSC.pack "finished\n"))
        , ("flushed Zstd stream", golden "zstd-flushed.xlog" (BSC.pack "flushed\n"))
        , ("concatenated Zstd frames", golden "zstd-concatenated.xlog" (BSC.pack "one\ntwo\n"))
        , ("buffer growth and exact limits", forM_ [9,13 :: Int] $ \magic -> do
            bytes <- fixture ("large-" ++ show magic ++ ".xlog")
            report <- decode strict { maxRecordOutputBytes = 262144 } bytes
            equal (BS.replicate 262144 65) (LBS.toStrict (decodedBytes report))
            expectKind OutputLimitExceeded (decodeXlog strict { maxRecordOutputBytes = 262143 } bytes))
        , ("total output limit", do
            let bytes = plain 1 "abc" <> plain 2 "def"
            report <- decode strict { maxTotalOutputBytes = 6 } bytes
            equal (BSC.pack "abcdef") (LBS.toStrict (decodedBytes report))
            expectKind OutputLimitExceeded (decodeXlog strict { maxTotalOutputBytes = 5 } bytes))
        , ("zero remaining budget and empty payload", do
            report <- decode strict { maxTotalOutputBytes = 1 } (plain 1 "x" <> record 9 2 BS.empty)
            equal 2 (decodedRecords report))
        , ("payload limit", expectKind PayloadLimitExceeded (decodeXlog strict { maxPayloadBytes = 2 } (plain 1 "abc")))
        , ("invalid limits", expectKind InvalidOptions (decodeXlog strict { maxPayloadBytes = 0 } BS.empty))
        , ("all truncated prefixes of each format", forM_ [1..13] $ \n -> do
            bytes <- fixture ("type-" ++ pad n ++ ".xlog")
            forM_ [0 .. BS.length bytes - 1] $ \len -> case parseFrame 100000 0 (BS.take len bytes) of
              Left _ -> pure ()
              Right _ -> assert "accepted truncated frame" False)
        , ("invalid offsets", forM_ [-1, 1000] $ \offset ->
            equal (Left (DecodeError offset InvalidOffset)) (parseFrame 100 offset BS.empty))
        , ("oversized Word32 length", do
            let bytes = BS.pack [1,255,255,255,255,0]
            equal (Left (DecodeError 0 PayloadLimitExceeded)) (parseFrame 100 0 bytes))
        , ("bad terminator", do
            let bytes = BS.init (plain 1 "abc") <> BS.singleton 99
            expectKind (InvalidTerminator 99) (decodeXlog strict bytes))
        , ("chunk length validation", forM_ [BS.singleton 0, BS.pack [5,0,1,2]] $ \bytes -> do
            equal (Left InvalidChunks) (unpackChunks bytes)
            expectKind InvalidChunks (decodeXlog strict (record 5 1 bytes)))
        , ("empty chunk terminates", equal (Right BS.empty) (unpackChunks (BS.pack [0,0,0,0])))
        , ("corrupt compressed payloads", forM_ [9,13] $ \magic -> do
            result <- decodeXlog strict (record magic 1 (BS.replicate 10 255))
            case result of
              Left (DecodeError 0 (NativeFailure _)) -> pure ()
              _ -> assert "accepted corrupt compression" False)
        , ("truncated raw stream", do
            bytes <- fixture "type-09.xlog"
            (frame, _) <- right (parseFrame 1000 0 bytes)
            result <- decodeXlog strict (record 9 1 (BS.init (framePayload frame)))
            case result of
              Left (DecodeError 0 (NativeFailure _)) -> pure ()
              _ -> assert "accepted truncated raw stream" False)
        , ("strict garbage failure", expectKind (InvalidMagic 255) (decodeXlog strict (BS.singleton 255 <> plain 1 "ok")))
        , ("recover prefix, middle and suffix", do
            let a = plain 1 "a"
                b = plain 3 "b"
                junk = BS.replicate 3 255
                bytes = junk <> a <> junk <> b <> junk
            report <- decode defaultDecodeOptions bytes
            equal (BSC.pack "ab") (LBS.toStrict (decodedBytes report))
            equal [SkippedBytes 0 3, SkippedBytes (3 + BS.length a) 3,
              SequenceGap (6 + BS.length a) 1 3, SkippedBytes (6 + BS.length a + BS.length b) 3]
              (diagnostics report))
        , ("no valid records", expectKind NoRecords (decodeXlog defaultDecodeOptions (BS.replicate 100 255)))
        , ("sequence wrap and resets", do
            report <- decode strict (mconcat [plain n "x" | n <- [65535,0,1,2,0,3,1,2]])
            equal [] (diagnostics report))
        , ("decode with pure capability backend", do
            let backend = Backend (\_ _ _ -> Identity (Left (NativeFailure "unexpected decompress")))
                                  (\_ _ -> Identity (Left (NativeFailure "unexpected ECDH")))
            report <- right (runIdentity (decodeXlogWith backend strict (plain 1 "pure")))
            equal (BSC.pack "pure") (LBS.toStrict (decodedBytes report)))
        , ("bounded parser fuzz", forM_ [0..999 :: Word32] $ \seed -> do
            let randoms = drop 1 (iterate (\x -> 1664525 * x + 1013904223) seed)
                bytes = BS.pack (take (fromIntegral (seed `mod` 200)) (map fromIntegral randoms))
            case findFrame 10000 0 bytes of
              Nothing -> pure ()
              Just (frame, next) -> assert "invalid recovery range" (frameOffset frame >= 0 && next <= BS.length bytes && next > frameOffset frame))
        ]
  runTests tests
