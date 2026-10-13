module Xlog.Decode (Backend (..), decodeXlogWith) where

import Data.Bits (xor)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.ByteString.Builder (byteString, toLazyByteString)
import Xlog.Crypto
import Xlog.Format
import Xlog.Types

-- | Explicit capabilities let the same decoder run in IO or a pure test monad.
data Backend m = Backend
  { decompress :: Compression -> Int -> ByteString -> m (Either ErrorKind ByteString)
  , sharedSecret :: PrivateKey -> ByteString -> m (Either ErrorKind ByteString)
  }

decodeXlogWith :: Monad m => Backend m -> DecodeOptions -> ByteString -> m (Either DecodeError DecodeReport)
decodeXlogWith backend options input
  | any (<= 0) [maxPayloadBytes options, maxRecordOutputBytes options, maxTotalOutputBytes options] =
      pure (Left (DecodeError 0 InvalidOptions))
  | BS.null input = pure (Right (DecodeReport mempty 0 []))
  | otherwise = go 0 Nothing 0 0 mempty []
  where
    go !offset !lastSeq !count !total !output notes
      | offset == BS.length input = done count output notes
      | otherwise = case parseFrame (maxPayloadBytes options) offset input of
          Right next -> consume lastSeq count total output notes next
          Left err -> case recovery options of
            Strict -> pure (Left err)
            Recover -> case findFrame (maxPayloadBytes options) (offset + 1) input of
              Just next@(frame, _) -> consume lastSeq count total output
                (SkippedBytes offset (frameOffset frame - offset) : notes) next
              Nothing
                | count == 0 -> pure (Left (DecodeError offset NoRecords))
                | otherwise -> done count output (SkippedBytes offset (BS.length input - offset) : notes)

    done count output notes = pure (Right (DecodeReport (toLazyByteString output) count (reverse notes)))

    consume lastSeq count total output notes (frame, next) = do
      let available = min (maxRecordOutputBytes options) (maxTotalOutputBytes options - total)
      result <- decodePayload backend options available frame
      case result of
        Left kind -> pure (Left (DecodeError (frameOffset frame) kind))
        Right bytes
          | BS.length bytes > available -> pure (Left (DecodeError (frameOffset frame) OutputLimitExceeded))
          | otherwise ->
              let seqNo = headerSequence (frameHeader frame)
                  newNotes = case (lastSeq, seqNo) of
                    (Just previous, Just current)
                      | current /= 0 && current /= 1 && current /= previous + 1 ->
                          SequenceGap (frameOffset frame) previous current : notes
                    _ -> notes
                  newSeq = case seqNo of
                    Just n | n /= 0 -> Just n
                    _ -> lastSeq
              in go next newSeq (count + 1) (total + BS.length bytes)
                   (output <> byteString bytes) newNotes

decodePayload :: Monad m => Backend m -> DecodeOptions -> Int -> Frame -> m (Either ErrorKind ByteString)
decodePayload backend options limit frame = case headerEncoding header of
  Plain -> checked payload
  XorPlain -> checked (xorPayload key payload)
  XorDeflate -> inflate (xorPayload key payload)
  ChunkedXorDeflate -> case unpackChunks payload of
    Left err -> pure (Left err)
    Right bytes -> inflate (xorPayload key bytes)
  Compressed codec -> decompress backend codec limit payload
  Encrypted codec -> case privateKey options of
    Nothing -> pure (Left MissingPrivateKey)
    Just secret -> do
      derived <- sharedSecret backend secret (headerPublicKey header)
      case derived >>= teaKeyFromBytes . BS.take 16 of
        Left err -> pure (Left err)
        Right teaKey -> decompress backend codec limit (teaDecrypt teaKey payload)
  where
    header = frameHeader frame
    payload = framePayload frame
    key = 0xcc `xor` headerMagic header `xor`
      maybe (fromIntegral (headerLength header)) fromIntegral (headerSequence header)
    inflate = decompress backend RawDeflate limit
    checked bytes = pure $ if BS.length bytes <= limit then Right bytes else Left OutputLimitExceeded
