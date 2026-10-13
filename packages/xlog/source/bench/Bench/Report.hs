module Bench.Report (Engine (..), Sample (..), renderCsv, renderReport) where

import Bench.Corpus
import Data.List (intercalate, sort)
import Text.Printf (printf)

data Engine = Baseline | Candidate | Python deriving (Eq, Show)

data Sample = Sample
  { sampleScenario :: !String
  , sampleEngine :: !Engine
  , sampleRound :: !Int
  , sampleSeconds :: !Double
  } deriving (Show)

renderCsv :: [Scenario] -> [Sample] -> String
renderCsv scenarios samples = unlines $
  ["scenario,engine,round,seconds,input_bytes,output_bytes,output_mib_per_second"] ++
  [ printf "%s,%s,%d,%.9f,%d,%d,%.3f" (sampleScenario sample) (show (sampleEngine sample))
      (sampleRound sample) (sampleSeconds sample) (encodedBytes scenario) (plainBytes scenario)
      (throughput scenario (sampleSeconds sample))
  | sample <- samples, scenario <- scenarios, scenarioName scenario == sampleScenario sample ]

median :: [Double] -> Double
median values = case drop (length values `div` 2 - if even (length values) then 1 else 0) (sort values) of
  a : b : _ | even (length values) -> (a + b) / 2
  a : _ -> a
  [] -> 0

throughput :: Scenario -> Double -> Double
throughput scenario seconds = fromIntegral (plainBytes scenario) / 1048576 / seconds

renderReport :: [String] -> [Scenario] -> [Sample] -> String
renderReport metadata scenarios samples = unlines $
  ["# Xlog migration benchmark", ""] ++ metadata ++
  [ "", "Wall-clock process time: startup + read + decode + write; warm filesystem cache, no fsync."
  , "Corpus generation, output deletion and byte-for-byte verification are outside the timed region."
  , "Each engine is warmed up first; measured order rotates by round. Every run must match the expected output."
  , "This compares the supplied programs and their default directory concurrency, not language performance in isolation."
  , "", tableLine (["Scenario", "Files", "Input MiB", "Output MiB"]
      ++ [label engine ++ " median ms" | engine <- engines]
      ++ ratiosHeader ++ ["Haskell output MiB/s"])
  , tableLine ("---" : replicate (4 + length engines + length ratiosHeader) "---:")
  ] ++ map row scenarios ++
  [ "", "Ratios divide the named program's time by Haskell's time: above 1 means Haskell is faster."
  , "", tableLine ("Scenario" : [label engine ++ " min–max ms" | engine <- engines])
  , tableLine ("---" : replicate (length engines) "---:")
  ] ++ map spread scenarios ++
  [ "", "Synthetic corpus: deterministic log-shaped text, distinct records, alternating DEFLATE/Zstd files in mixed directories."
  , "Encrypted records use secp256k1 ECDH + 16-round TEA with the supplied legacy key; the key is never written to this report."
  , "All files in a given codec reuse the same generated record sequence. Results are not a production-log workload guarantee."
  , "Large variance and sub-10ms cases are sensitive to process startup, scheduler activity and filesystem cache effects."
  , "Raw measured samples are in `samples.csv`."
  ]
  where
    engines = [Baseline, Candidate] ++ [Python | any ((== Python) . sampleEngine) samples]
    label Baseline = "C++"
    label Candidate = "Haskell"
    label Python = "Python"
    ratiosHeader = [label engine ++ " / Haskell" | engine <- engines, engine /= Candidate]
    tableLine cells = "| " ++ intercalate " | " cells ++ " |"
    times scenario engine = [sampleSeconds sample | sample <- samples,
      sampleScenario sample == scenarioName scenario, sampleEngine sample == engine]
    row scenario =
      let candidate = median (times scenario Candidate)
      in tableLine $
           [ scenarioName scenario, show (length (scenarioFiles scenario))
           , printf "%.3f" (fromIntegral (encodedBytes scenario) / 1048576 :: Double)
           , printf "%.3f" (fromIntegral (plainBytes scenario) / 1048576 :: Double)
           ] ++ [printf "%.3f" (median (times scenario engine) * 1000) | engine <- engines]
           ++ [printf "%.3fx" (median (times scenario engine) / candidate) | engine <- engines, engine /= Candidate]
           ++ [printf "%.2f" (throughput scenario candidate)]
    range scenario engine = case sort (times scenario engine) of
      [] -> "n/a"
      low : rest -> printf "%.3f–%.3f" (low * 1000) (foldl max low rest * 1000)
    spread scenario = tableLine (scenarioName scenario : [range scenario engine | engine <- engines])
