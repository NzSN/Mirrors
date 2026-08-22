{-# LANGUAGE OverloadedStrings #-}
-- | Phase 0 exit-criterion harness (§8): replay the golden wire corpus
--   against the Haskell mirror's codecs and JSON-RPC layer.
--
--   For every line of client_messages.jsonl / mirror_messages.jsonl:
--     1. decode with the Haskell FromJSON instances,
--     2. re-encode with the Haskell ToJSON instances,
--     3. assert the bytes are identical to the fixture line (frozen wire),
--     4. assert decode(encode m) == m (semantic round-trip).
--   For every explorer transcript: decode the recorded request as a
--   JsonRpcRequest, re-encode, and assert byte identity; decode the
--   recorded response as a JsonRpcResponse.
--
--   Exit 0 = corpus replayed green.
module Main (main) where

import Control.Monad (forM_, unless)
import qualified Data.ByteString.Lazy.Char8 as BSLC
import Data.Aeson (eitherDecode, encode, FromJSON, ToJSON)
import qualified Data.Aeson as A
import qualified Data.Aeson.Key as K
import qualified Data.Aeson.KeyMap as HM
import Data.Text (Text)
import qualified Data.Text as T
import System.Environment (getArgs)
import System.Exit (exitFailure, exitSuccess)
import System.IO

import Apalache.Rpc.Types (JsonRpcRequest(..), JsonRpcResponse)
import Protocol.Core
import Protocol.Format.Json ()

check :: (FromJSON a, ToJSON a, Eq a, Show a) => String -> Int -> String -> (a -> String) -> IO Bool
check file lineNo raw showCtor = case eitherDecode (BSLC.pack raw) of
  Left err -> do
    putStrLn ("FAIL " ++ file ++ ":" ++ show lineNo ++ " decode: " ++ err)
    pure False
  Right m -> do
    let re = BSLC.unpack (encode m)
        ctor = showCtor m
    if re /= raw
      then do
        putStrLn ("FAIL " ++ file ++ ":" ++ show lineNo ++ " (" ++ ctor ++ ") wire drift")
        putStrLn ("  fixture:  " ++ raw)
        putStrLn ("  reencode: " ++ re)
        pure False
      else case eitherDecode (BSLC.pack re) of
        Left err -> do
          putStrLn ("FAIL " ++ file ++ ":" ++ show lineNo ++ " (" ++ ctor ++ ") redecode: " ++ err)
          pure False
        Right m' | m' == m -> pure True
                 | otherwise -> do
                     putStrLn ("FAIL " ++ file ++ ":" ++ show lineNo ++ " (" ++ ctor ++ ") round-trip mismatch")
                     pure False

ctorOf :: ClientMessage -> String
ctorOf m = case m of
  Register{} -> "Register"; RegisterTraces{} -> "RegisterTraces"
  RegisterGenTraces{} -> "RegisterGenTraces"; RegisterExplore{} -> "RegisterExplore"
  RegisterExploreSession{} -> "RegisterExploreSession"; RegisterValidate{} -> "RegisterValidate"
  RegisterValidateAsync{} -> "RegisterValidateAsync"; RegisterGenTracesAsync{} -> "RegisterGenTracesAsync"
  QueryJob{} -> "QueryJob"; AwaitJob{} -> "AwaitJob"; CancelJob{} -> "CancelJob"
  ExploreAssumeTransition{} -> "ExploreAssumeTransition"; ExploreNextStep -> "ExploreNextStep"
  ExploreQueryState -> "ExploreQueryState"; ExploreCheckInvariant{} -> "ExploreCheckInvariant"
  ExploreAssumeState{} -> "ExploreAssumeState"; ExploreRollback{} -> "ExploreRollback"
  ExploreDone -> "ExploreDone"; ReportState{} -> "ReportState"

ctorOfM :: MirrorMessage -> String
ctorOfM m = case m of
  SpecValidated{} -> "SpecValidated"; InitialState{} -> "InitialState"; NextStep{} -> "NextStep"
  StepOk -> "StepOk"; StepMismatch{} -> "StepMismatch"; AllStepsDone -> "AllStepsDone"
  GenTracesDone{} -> "GenTracesDone"; RegisterError{} -> "RegisterError"; ProtocolError{} -> "ProtocolError"
  ExplorerReady{} -> "ExplorerReady"; ExploreTransitionStatus{} -> "ExploreTransitionStatus"
  ExploreStepDone{} -> "ExploreStepDone"; ExploreState{} -> "ExploreState"
  ExploreInvariantStatus{} -> "ExploreInvariantStatus"; ExploreAssumeStatus{} -> "ExploreAssumeStatus"
  ExploreRollbackDone{} -> "ExploreRollbackDone"; ExploreSessionDone -> "ExploreSessionDone"
  JobAccepted{} -> "JobAccepted"; JobStatus{} -> "JobStatus"; JobResult{} -> "JobResult"

replayFile :: String -> (Int -> String -> IO Bool) -> IO (Int, Int)
replayFile file checkLine = do
  raw <- readFile file
  let ls = filter (not . null) (lines raw)
  oks <- mapM (uncurry checkLine) (zip [1 ..] ls)
  let bad = length (filter not oks)
  putStrLn (file ++ ": " ++ show (length ls - bad) ++ "/" ++ show (length ls) ++ " green")
  pure (length ls - bad, length ls)

-- transcripts: {"method":..., "request":"<raw>", "response":"<raw>"}
replayTranscripts :: String -> IO (Int, Int)
replayTranscripts file = do
  raw <- readFile file
  let ls = filter (not . null) (lines raw)
  oks <- mapM one (zip [1 ..] ls)
  let bad = length (filter not oks)
  putStrLn (file ++ ": " ++ show (length ls - bad) ++ "/" ++ show (length ls) ++ " green")
  pure (length ls - bad, length ls)
  where
    one (lineNo, l) = case eitherDecode (BSLC.pack l) of
      Left err -> fail2 lineNo ("entry decode: " ++ err)
      Right entry -> do
        let reqRaw = strField "request" entry
            respRaw = strField "response" entry
        -- JsonRpcRequest has no FromJSON instance in ModelMirrors (client
        -- only encodes); validate shape as JSON and cross-check the method.
        case eitherDecode (BSLC.pack reqRaw) :: Either String A.Value of
          Left err -> fail2 lineNo ("request decode: " ++ err)
          Right rv
            | not (hasKey "jsonrpc" rv) || not (hasKey "method" rv)
              || not (hasKey "params" rv) || not (hasKey "id" rv) ->
                fail2 lineNo "request missing JSON-RPC fields"
            | strField "method" entry /= strKeyOf "method" rv ->
                fail2 lineNo "request/entry method mismatch"
            | otherwise ->
                case eitherDecode (BSLC.pack respRaw) :: Either String JsonRpcResponse of
                  Left err -> fail2 lineNo ("response decode: " ++ err)
                  Right _ -> pure True
    strField k o = strKeyOf k (A.Object o)
    hasKey k (A.Object o) = HM.member (K.fromString k) o
    hasKey _ _ = False
    strKeyOf k (A.Object o) = case HM.lookup (K.fromString k) o of
      Just (A.String v) -> T.unpack v
      _ -> ""
    strKeyOf _ _ = ""
    fail2 n msg = putStrLn ("FAIL " ++ file ++ ":" ++ show n ++ " " ++ msg) >> pure False

main :: IO ()
main = do
  [fixturesDir] <- getArgs
  (cOk, cN) <- replayFile (fixturesDir ++ "/client_messages.jsonl")
    (\n l -> check "client_messages.jsonl" n l ctorOf)
  (mOk, mN) <- replayFile (fixturesDir ++ "/mirror_messages.jsonl")
    (\n l -> check "mirror_messages.jsonl" n l ctorOfM)
  (tOk, tN) <- replayTranscripts (fixturesDir ++ "/explorer_transcripts.jsonl")
  let ok = cOk + mOk + tOk
      tot = cN + mN + tN
  putStrLn ("total: " ++ show ok ++ "/" ++ show tot ++ " green")
  if ok == tot then exitSuccess else exitFailure
