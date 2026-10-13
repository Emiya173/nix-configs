module Xlog.Types
  ( Compression (..), Encoding (..), Header (..), Frame (..)
  , Recovery (..), DecodeOptions (..), defaultDecodeOptions
  , ErrorKind (..), DecodeError (..), Diagnostic (..), DecodeReport (..)
  , PrivateKey
  ) where

import Data.ByteString (ByteString)
import qualified Data.ByteString.Lazy as LBS
import Data.Word (Word8, Word16, Word32)
import Xlog.Internal.Key (PrivateKey)

data Compression = RawDeflate | Zstd deriving (Eq, Show)

-- Algebraic data types describe the actual payload transformations.
data Encoding
  = XorPlain
  | XorDeflate
  | ChunkedXorDeflate
  | Plain
  | Compressed !Compression
  | Encrypted !Compression
  deriving (Eq, Show)

data Header = Header
  { headerMagic :: !Word8
  , headerEncoding :: !Encoding
  , headerSequence :: !(Maybe Word16)
  , headerBeginHour :: !(Maybe Word8)
  , headerEndHour :: !(Maybe Word8)
  , headerLength :: !Word32
  , headerPublicKey :: !ByteString
  } deriving (Eq, Show)

data Frame = Frame
  { frameOffset :: !Int
  , frameHeader :: !Header
  , framePayload :: !ByteString
  } deriving (Eq, Show)

data Recovery = Strict | Recover deriving (Eq, Show)

data DecodeOptions = DecodeOptions
  { recovery :: !Recovery
  , privateKey :: !(Maybe PrivateKey)
  , maxPayloadBytes :: !Int
  , maxRecordOutputBytes :: !Int
  , maxTotalOutputBytes :: !Int
  } deriving (Show)

defaultDecodeOptions :: DecodeOptions
defaultDecodeOptions = DecodeOptions Recover Nothing (64 * 1024 * 1024)
  (256 * 1024 * 1024) (1024 * 1024 * 1024)

data ErrorKind
  = InvalidMagic !Word8
  | TruncatedHeader
  | TruncatedPayload
  | InvalidTerminator !Word8
  | InvalidChunks
  | InvalidOffset
  | NoRecords
  | InvalidOptions
  | PayloadLimitExceeded
  | OutputLimitExceeded
  | MissingPrivateKey
  | InvalidPrivateKey
  | InvalidPublicKey
  | InvalidTeaKey
  | NativeFailure !String
  deriving (Eq, Show)

data DecodeError = DecodeError
  { errorOffset :: !Int
  , errorKind :: !ErrorKind
  } deriving (Eq, Show)

data Diagnostic
  = SkippedBytes { skippedOffset :: !Int, skippedLength :: !Int }
  | SequenceGap { sequenceOffset :: !Int, previousSequence :: !Word16, actualSequence :: !Word16 }
  deriving (Eq, Show)

data DecodeReport = DecodeReport
  { decodedBytes :: !LBS.ByteString
  , decodedRecords :: !Int
  , diagnostics :: ![Diagnostic]
  } deriving (Eq, Show)
