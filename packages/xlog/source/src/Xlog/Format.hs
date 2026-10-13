module Xlog.Format (parseFrame, findFrame, unpackChunks) where

import Control.Monad (unless)
import Data.Binary.Get (Get, getByteString, getWord8, getWord16le, getWord32le, isEmpty, runGetOrFail, skip)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import Data.Word (Word8)
import Xlog.Types

encoding :: Word8 -> Maybe Encoding
encoding magic = case magic of
  1 -> Just XorPlain
  2 -> Just XorDeflate
  3 -> Just XorPlain
  4 -> Just XorDeflate
  5 -> Just ChunkedXorDeflate
  6 -> Just Plain
  7 -> Just (Encrypted RawDeflate)
  8 -> Just Plain
  9 -> Just (Compressed RawDeflate)
  10 -> Just Plain
  11 -> Just Plain
  12 -> Just (Encrypted Zstd)
  13 -> Just (Compressed Zstd)
  _ -> Nothing

-- | Parse one record at an absolute byte offset. All wire integers are LE.
-- Returns the next absolute offset; no unchecked access to input is needed.
parseFrame :: Int -> Int -> ByteString -> Either DecodeError (Frame, Int)
parseFrame limit offset input
  | offset < 0 || offset >= BS.length input = bad InvalidOffset
  | otherwise = do
      magic <- maybe (bad TruncatedHeader) (Right . fst) (BS.uncons remaining)
      codec <- maybe (bad (InvalidMagic magic)) Right (encoding magic)
      let headerSize | magic <= 2 = 5
                     | magic <= 5 = 9
                     | otherwise = 73
      unless (BS.length remaining >= headerSize) (bad TruncatedHeader)
      header <- case runGetOrFail (getHeader magic codec) (LBS.fromStrict remaining) of
        Left _ -> bad TruncatedHeader
        Right (_, _, h) -> Right h
      let size = toInteger (headerLength header)
      unless (limit >= 0 && size <= toInteger limit) (bad PayloadLimitExceeded)
      -- Compare before converting Word32 to Int, including on 32-bit hosts.
      unless (size + toInteger headerSize + 1 <= toInteger (BS.length remaining))
        (bad TruncatedPayload)
      let len = fromIntegral (headerLength header)
          body = BS.drop headerSize remaining
      case BS.uncons (BS.drop len body) of
        Just (0, _) -> Right (Frame offset header (BS.take len body), offset + headerSize + len + 1)
        Just (byte, _) -> bad (InvalidTerminator byte)
        Nothing -> bad TruncatedPayload
  where
    remaining = BS.drop offset input
    bad kind = Left (DecodeError offset kind)

getHeader :: Word8 -> Encoding -> Get Header
getHeader magic codec = do
  skip 1
  (seqNo, begin, end) <- if magic <= 2
    then pure (Nothing, Nothing, Nothing)
    else (,,) <$> (Just <$> getWord16le) <*> (Just <$> getWord8) <*> (Just <$> getWord8)
  len <- getWord32le
  pub <- if magic >= 6 then getByteString 64 else pure BS.empty
  pure (Header magic codec seqNo begin end len pub)

-- | Resynchronise on the next structurally valid record, without decoding it.
findFrame :: Int -> Int -> ByteString -> Maybe (Frame, Int)
findFrame limit start input = go (max 0 start)
  where
    go offset = case BS.findIndex (\b -> b >= 1 && b <= 13) (BS.drop offset input) of
      Nothing -> Nothing
      Just distance ->
        let candidate = offset + distance
        in case parseFrame limit candidate input of
          Right frame -> Just frame
          Left _ -> go (candidate + 1)

-- | Type 0x05 prefixes each fragment with an unencrypted LE Word16 length.
unpackChunks :: ByteString -> Either ErrorKind ByteString
unpackChunks input = case runGetOrFail chunks (LBS.fromStrict input) of
  Left _ -> Left InvalidChunks
  Right (_, _, parts) -> Right (BS.concat parts)
  where
    chunks = go []
    go acc = do
      done <- isEmpty
      if done then pure (reverse acc) else do
        size <- getWord16le
        part <- getByteString (fromIntegral size)
        go (part : acc)
