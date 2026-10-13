{-# LANGUAGE ForeignFunctionInterface #-}
-- The generator owns its compression bindings; it never imports Xlog.Native.
module Fixture.Compression (Compression (..), compress) where

#include <zlib.h>
#include <zstd.h>

import Control.Exception (bracket, bracket_)
import Control.Monad (unless, when)
import qualified Data.ByteString as BS
import Foreign (Ptr, allocaBytes, fillBytes, peekByteOff, pokeByteOff)
import Foreign.C.String (CString, peekCString)
import Foreign.C.Types (CInt (..), CSize (..), CUInt (..))
import Foreign.Marshal.Alloc (free, mallocBytes)
import Foreign.Ptr (nullPtr)

data Compression = DeflateFinished | DeflateFlushed | ZstdFrame | ZstdFlushed

foreign import ccall unsafe "zlibVersion"
  zlibVersion :: IO CString
foreign import ccall safe "deflateInit2_"
  deflateInit :: Ptr () -> CInt -> CInt -> CInt -> CInt -> CInt -> CString -> CInt -> IO CInt
foreign import ccall safe "deflate"
  deflate :: Ptr () -> CInt -> IO CInt
foreign import ccall unsafe "deflateEnd"
  deflateEnd :: Ptr () -> IO CInt
foreign import ccall unsafe "ZSTD_createCCtx"
  createCCtx :: IO (Ptr ())
foreign import ccall unsafe "ZSTD_freeCCtx"
  freeCCtx :: Ptr () -> IO CSize
foreign import ccall unsafe "ZSTD_CCtx_setParameter"
  setParameter :: Ptr () -> CInt -> CInt -> IO CSize
foreign import ccall safe "ZSTD_compressStream2"
  compressStream :: Ptr () -> Ptr () -> Ptr () -> CInt -> IO CSize
foreign import ccall unsafe "ZSTD_isError"
  isError :: CSize -> IO CUInt
foreign import ccall unsafe "ZSTD_getErrorName"
  errorName :: CSize -> IO CString
foreign import ccall unsafe "ZSTD_compressBound"
  compressBound :: CSize -> IO CSize
foreign import ccall safe "ZSTD_compress"
  compressFrame :: Ptr a -> CSize -> Ptr b -> CSize -> CInt -> IO CSize

compress :: Compression -> BS.ByteString -> IO BS.ByteString
compress codec input = case codec of
  DeflateFinished -> rawDeflate True input
  DeflateFlushed -> rawDeflate False input
  ZstdFrame -> zstdFrame input
  ZstdFlushed -> zstdFlushed input

chunkSize :: Int
chunkSize = 65536

rawDeflate :: Bool -> BS.ByteString -> IO BS.ByteString
rawDeflate finish input = BS.useAsCStringLen input $ \(source, len) ->
  allocaBytes #{size z_stream} $ \stream -> allocaBytes chunkSize $ \output -> do
    when (toInteger len > toInteger (maxBound :: CUInt)) (fail "fixture exceeds zlib input range")
    fillBytes stream 0 #{size z_stream}
    #{poke z_stream, next_in} stream source
    #{poke z_stream, avail_in} stream (fromIntegral len :: CUInt)
    version <- zlibVersion
    let acquire = do
          result <- deflateInit stream (#{const Z_DEFAULT_COMPRESSION}) #{const Z_DEFLATED}
            (-15) 8 #{const Z_DEFAULT_STRATEGY} version #{size z_stream}
          unless (result == #{const Z_OK}) (fail "deflateInit2 failed")
        release = do
          -- Z_SYNC_FLUSH intentionally leaves an unfinished stream; deflateEnd
          -- still releases it, but may report Z_DATA_ERROR for that state.
          _ <- deflateEnd stream
          pure ()
        loop parts = do
          #{poke z_stream, next_out} stream output
          #{poke z_stream, avail_out} stream (fromIntegral chunkSize :: CUInt)
          before <- #{peek z_stream, avail_in} stream :: IO CUInt
          status <- deflate stream (if finish then #{const Z_FINISH} else #{const Z_SYNC_FLUSH})
          unless (status == #{const Z_OK} || status == #{const Z_STREAM_END}) (fail "deflate failed")
          available <- #{peek z_stream, avail_out} stream :: IO CUInt
          remaining <- #{peek z_stream, avail_in} stream :: IO CUInt
          let produced = chunkSize - fromIntegral available
          part <- BS.packCStringLen (output, produced)
          if status == #{const Z_STREAM_END} || (not finish && remaining == 0 && available > 0)
            then pure (BS.concat (reverse (part : parts)))
            else do
              when (remaining == before && produced == 0) (fail "deflate made no progress")
              loop (part : parts)
    bracket_ acquire release (loop [])

checkZstd :: CSize -> IO ()
checkZstd status = do
  bad <- isError status
  when (bad /= 0) (errorName status >>= peekCString >>= fail)

zstdFrame :: BS.ByteString -> IO BS.ByteString
zstdFrame input = BS.useAsCStringLen input $ \(source, len) -> do
  bound <- compressBound (fromIntegral len)
  when (toInteger bound > toInteger (maxBound :: Int)) (fail "fixture compression buffer too large")
  bracket (mallocBytes (fromIntegral bound)) free $ \output -> do
    size <- compressFrame output bound source (fromIntegral len) 3
    checkZstd size
    BS.packCStringLen (output, fromIntegral size)

zstdFlushed :: BS.ByteString -> IO BS.ByteString
zstdFlushed input = BS.useAsCStringLen input $ \(source, len) ->
  bracket acquire release $ \ctx ->
    allocaBytes #{size ZSTD_inBuffer} $ \inp ->
      allocaBytes #{size ZSTD_outBuffer} $ \out ->
        allocaBytes chunkSize $ \buffer -> do
          setParameter ctx #{const ZSTD_c_windowLog} 10 >>= checkZstd
          #{poke ZSTD_inBuffer, src} inp source
          #{poke ZSTD_inBuffer, size} inp (fromIntegral len :: CSize)
          #{poke ZSTD_inBuffer, pos} inp (0 :: CSize)
          let loop parts = do
                before <- #{peek ZSTD_inBuffer, pos} inp :: IO CSize
                #{poke ZSTD_outBuffer, dst} out buffer
                #{poke ZSTD_outBuffer, size} out (fromIntegral chunkSize :: CSize)
                #{poke ZSTD_outBuffer, pos} out (0 :: CSize)
                status <- compressStream ctx out inp #{const ZSTD_e_flush}
                checkZstd status
                consumed <- #{peek ZSTD_inBuffer, pos} inp :: IO CSize
                produced <- #{peek ZSTD_outBuffer, pos} out :: IO CSize
                part <- BS.packCStringLen (buffer, fromIntegral produced)
                if status == 0 && consumed == fromIntegral len
                  then pure (BS.concat (reverse (part : parts)))
                  else do
                    when (consumed == before && produced == 0) (fail "Zstd made no progress")
                    loop (part : parts)
          loop []
  where
    acquire = do
      ctx <- createCCtx
      when (ctx == nullPtr) (fail "ZSTD_createCCtx failed")
      pure ctx
    release ctx = freeCCtx ctx >> pure ()
