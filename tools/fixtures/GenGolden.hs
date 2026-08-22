{-# LANGUAGE OverloadedStrings #-}
-- | Golden wire-corpus generator (Docs/lean4-refactor-design.md, §8 Phase 0).
--
--   Produces, under <outDir>:
--     client_messages.jsonl      one raw wire line per representative ClientMessage
--     mirror_messages.jsonl      one raw wire line per representative MirrorMessage
--     explorer_transcripts.jsonl one entry per explorer JSON-RPC exchange
--                                (raw request bytes sent by the Haskell client
--                                + raw response bytes served, byte-exact)
--     manifest.json              ctor/variant name per line, per file
--     metadata.json              upstream commit, corpus shape
--
--   The Haskell ModelMirrors tree is consumed read-only as an external
--   artifact pinned by commit (passed as argv[2]).
module Main (main) where

import Control.Concurrent (forkIO)
import Control.Exception (SomeException, try)
import Control.Monad (forever)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.ByteString.Lazy as BSL
import qualified Data.ByteString.Lazy.Char8 as BSLC
import Data.Aeson (encode, object, (.=))
import qualified Data.Aeson as A
import qualified Network.Socket.ByteString as NSB
import qualified Data.Aeson.Key as K
import qualified Data.Aeson.KeyMap as KM
import Data.IORef
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Network.Socket
import Data.Char (toLower)
import System.Environment (getArgs)

import Apalache.Rpc.Client
import Apalache.Rpc.Types
import Apalache.Types
import Protocol.Core
import Protocol.Format.Json ()  -- aeson instances (orphans) for the wire format

-- ---------------------------------------------------------------------------
-- representative payloads
-- ---------------------------------------------------------------------------

cfg, cfgMin :: ApalacheConfig
cfg = ApalacheConfig
  { specPath = "specs/HourClock.tla"
  , initPredicate = Just "Init"
  , nextPredicate = Just "Next"
  , constInit = Nothing
  , invariant = "Inv"
  , lengthBound = 10
  , paramVarNames = "p"
  }
cfgMin = ApalacheConfig "HourClock.tla" Nothing Nothing Nothing "" 10 ""

tc :: TraceGenerationConfig
tc = TraceGenerationConfig 3 (Just "view")

spec :: ApalacheSpec
spec = ApalacheSpec [T.pack ("---- MODULE HourClock ----" ++ ['\n'] ++ "----")]

-- | Exercises every 'Value' constructor.
richState :: Map Text Value
richState = M.fromList
  [ ("h", VInt 12)
  , ("ok", VBool True)
  , ("name", VStr "tick")
  , ("s", VSet [VInt 1, VInt 2, VInt 3])
  , ("seq", VSeq [VInt 1, VStr "x"])
  , ("tup", VTuple [VInt 1, VBool False])
  , ("rec", VRecord (M.fromList [("a", VInt 42), ("b", VNull)]))
  , ("m", VMap (M.fromList [("1", VBool True)]))
  , ("v", VVariant "Some" (VInt 7))
  , ("u", VUnserializable "SetOfSets")
  , ("z", VNull)
  ]

simpleState :: Map Text Value
simpleState = M.fromList [("h", VInt 0), ("action_taken", VStr "Init")]

-- | Exercises all 7 'DiffHint' constructors.
hints :: [DiffHint]
hints =
  [ HValueMismatch [Field "h", Index 0] (VInt 1) (VInt 2)
  , HMissing [Field "k"] (VInt 9)
  , HExtra [Index 3] (VStr "x")
  , HMissingElem [Field "s"] (VInt 4)
  , HExtraElem [Field "s"] (VInt 5)
  , HTypeMismatch [Field "h"] (VInt 1) (VBool False)
  , HTruncated [Field "s", Index 50]
  ]

clientMessages :: [(String, ClientMessage)]
clientMessages =
  [ ("Register.full", Register cfg tc (Just spec))
  , ("Register.noSpec", Register cfgMin tc Nothing)
  , ("RegisterTraces", RegisterTraces cfg ["out/itf/trace1.itf.json", "out/itf/trace2.itf.json"])
  , ("RegisterGenTraces.full", RegisterGenTraces cfg tc (Just "out/itf") (Just spec))
  , ("RegisterGenTraces.min", RegisterGenTraces cfgMin tc Nothing Nothing)
  , ("RegisterExplore", RegisterExplore spec ["Inv"] ["Export"] 25)
  , ("RegisterExploreSession", RegisterExploreSession spec ["InvA", "InvB"] [])
  , ("RegisterValidate", RegisterValidate cfg 10 (Just spec))
  , ("RegisterValidate.noSpec", RegisterValidate cfg 100 Nothing)
  , ("RegisterValidateAsync", RegisterValidateAsync cfg 5 (Just spec))
  , ("RegisterGenTracesAsync", RegisterGenTracesAsync cfg tc (Just "out/itf") (Just spec))
  , ("QueryJob", QueryJob (JobId "job-7f3a"))
  , ("AwaitJob", AwaitJob (JobId "job-7f3a") (Just 30))
  , ("AwaitJob.noTimeout", AwaitJob (JobId "job-7f3a") Nothing)
  , ("CancelJob", CancelJob (JobId "job-7f3a"))
  , ("ExploreAssumeTransition", ExploreAssumeTransition 2)
  , ("ExploreNextStep", ExploreNextStep)
  , ("ExploreQueryState", ExploreQueryState)
  , ("ExploreCheckInvariant", ExploreCheckInvariant 1)
  , ("ExploreAssumeState", ExploreAssumeState richState)
  , ("ExploreRollback", ExploreRollback 3)
  , ("ExploreDone", ExploreDone)
  , ("ReportState", ReportState simpleState)
  , ("ReportState.rich", ReportState richState)
  ]

mirrorMessages :: [(String, MirrorMessage)]
mirrorMessages =
  [ ("SpecValidated.ok", SpecValidated SpecValid)
  , ("SpecValidated.invalid", SpecValidated (SpecInvalid "Invariant violated"))
  , ("InitialState", InitialState "Init" simpleState)
  , ("NextStep", NextStep "Tick" richState)
  , ("StepOk", StepOk)
  , ("StepMismatch", StepMismatch simpleState richState hints)
  , ("StepMismatch.noHints", StepMismatch simpleState richState [])
  , ("AllStepsDone", AllStepsDone)
  , ("GenTracesDone", GenTracesDone ["out/itf/trace1.itf.json"] [])
  , ("RegisterError", RegisterError "apalache failed")
  , ("ProtocolError", ProtocolError "unexpected message")
  , ("ExplorerReady", ExplorerReady 2 3 1)
  , ("ExploreTransitionStatus", ExploreTransitionStatus "ENABLED")
  , ("ExploreStepDone", ExploreStepDone 4)
  , ("ExploreState", ExploreState richState)
  , ("ExploreInvariantStatus", ExploreInvariantStatus "SATISFIED")
  , ("ExploreAssumeStatus", ExploreAssumeStatus "ENABLED")
  , ("ExploreRollbackDone", ExploreRollbackDone 2)
  , ("ExploreSessionDone", ExploreSessionDone)
  , ("JobAccepted.validate", JobAccepted (JobId "job-7f3a") ValidateJob)
  , ("JobAccepted.genTraces", JobAccepted (JobId "job-9") GenTracesJob)
  , ("JobStatus.pending", JobStatus (JobId "job-7f3a") JobPending)
  , ("JobStatus.running", JobStatus (JobId "job-7f3a") JobRunning)
  , ("JobStatus.done", JobStatus (JobId "job-7f3a") JobDone)
  , ("JobStatus.failed", JobStatus (JobId "job-7f3a") JobFailed)
  , ("JobStatus.cancelled", JobStatus (JobId "job-7f3a") JobCancelled)
  , ("JobStatus.unknown", JobStatus (JobId "job-gone") JobUnknown)
  , ("JobResult.validate", JobResult (JobId "job-7f3a") (JobValidateDone SpecValid))
  , ("JobResult.genTraces", JobResult (JobId "job-9") (JobGenTracesDone ["out/itf/t1.itf.json"] []))
  , ("JobResult.infra", JobResult (JobId "job-9") (JobInfraError "worker died"))
  ]

-- ---------------------------------------------------------------------------
-- canned mock explorer server (raw sockets, HTTP/1.1, loopback only)
-- ---------------------------------------------------------------------------

cannedResult :: String -> A.Value
cannedResult "health" = object ["status" .= ("ok" :: Text)]
cannedResult "loadSpec" = object
  [ "sessionId" .= ("sess-1" :: Text)
  , "snapshotId" .= (0 :: Int)
  , "specParameters" .= object
      [ "initTransitions" .= [object ["index" .= (0 :: Int), "labels" .= ["Init" :: Text]]]
      , "nextTransitions" .=
          [ object ["index" .= (0 :: Int), "labels" .= ["Tick" :: Text]]
          , object ["index" .= (1 :: Int), "labels" .= ["Reset" :: Text]] ]
      , "stateInvariants" .= [object ["index" .= (0 :: Int), "labels" .= ["Inv" :: Text]]]
      , "actionInvariants" .= ([] :: [A.Value])
      ]
  ]
cannedResult "assumeTransition" = object
  [ "sessionId" .= ("sess-1" :: Text), "snapshotId" .= (1 :: Int)
  , "transitionId" .= (0 :: Int), "status" .= ("ENABLED" :: Text) ]
cannedResult "nextStep" = object
  [ "sessionId" .= ("sess-1" :: Text), "snapshotId" .= (2 :: Int), "newStepNo" .= (1 :: Int) ]
cannedResult "checkInvariant" = object
  [ "sessionId" .= ("sess-1" :: Text), "invariantStatus" .= ("SATISFIED" :: Text), "trace" .= A.Null ]
cannedResult "query" = object
  [ "sessionId" .= ("sess-1" :: Text), "trace" .= A.Null
  , "state" .= object ["h" .= object ["#bigint" .= ("1" :: Text)], "ok" .= A.Bool True]
  , "operatorValue" .= A.Null ]
cannedResult "assumeState" = object
  [ "sessionId" .= ("sess-1" :: Text), "snapshotId" .= (3 :: Int), "status" .= ("ENABLED" :: Text) ]
cannedResult _ = A.Null  -- rollback / disposeSpec / unknown: null result

knownMethods :: [String]
knownMethods =
  [ "health", "loadSpec", "assumeTransition", "nextStep", "checkInvariant"
  , "query", "assumeState", "rollback", "disposeSpec" ]

data MockServer = MockServer
  { mockPort :: Int
  , mockLog  :: IORef [(String, BSL.ByteString, BSL.ByteString)] -- (method, raw request, raw response)
  }

withMockServer :: (MockServer -> IO a) -> IO a
withMockServer act = do
  addr : _ <- getAddrInfo (Just defaultHints { addrFlags = [AI_PASSIVE] }) (Just "127.0.0.1") (Just "0")
  s <- socket (addrFamily addr) (addrSocketType addr) (addrProtocol addr)
  bind s (addrAddress addr)
  listen s 4
  SockAddrInet p _ <- getSocketName s
  logRef <- newIORef []
  _ <- forkIO $ forever $ do
    (c, _) <- accept s
    _ <- try (serveConn logRef c) :: IO (Either SomeException ())
    close c
  r <- act (MockServer (fromIntegral p) logRef)
  close s
  pure r

serveConn :: IORef [(String, BSL.ByteString, BSL.ByteString)] -> Socket -> IO ()
serveConn logRef c = do
  mreq <- readHttpRequest c
  case mreq of
    Nothing -> pure ()
    Just rawReq -> do
      let meth = reqMethod rawReq
          replyObj =
            let rid  = fromMaybe A.Null (KM.lookup (K.fromString "id") (objOf (decoded rawReq)))
                body | elem meth knownMethods =
                          ["result" .= cannedResult meth]
                     | otherwise =
                          ["error" .= object ["code" .= (-32601 :: Int), "message" .= ("method not found" :: Text)]]
            in object (["jsonrpc" .= ("2.0" :: Text), "id" .= rid] ++ body)
          rawResp = encode replyObj
      modifyIORef' logRef ((meth, rawReq, rawResp) :)
      sendAll' c $ BSC.pack $
        "HTTP/1.1 200 OK" ++ ['\r','\n'] ++ "Content-Type: application/json" ++ ['\r','\n'] ++ "Content-Length: "
        ++ show (BSL.length rawResp) ++ ['\r','\n'] ++ "Connection: close" ++ ['\r','\n','\r','\n']
        ++ BSLC.unpack rawResp
  where
    decoded rawReq = fromMaybe A.Null (A.decode rawReq :: Maybe A.Value)
    objOf (A.Object o) = o
    objOf _ = KM.empty
    reqMethod rawReq = case decoded rawReq of
      A.Object o -> case KM.lookup (K.fromString "method") o of
        Just (A.String t) -> T.unpack t
        _ -> "?"
      _ -> "?"

readHttpRequest :: Socket -> IO (Maybe BSL.ByteString)
readHttpRequest c = hdr ""
  where
    hdr acc = do
      chunk <- NSB.recv c 4096
      if BS.null chunk then pure Nothing
      else do
        let acc' = acc ++ BSC.unpack chunk
        case findSub ([ '\r','\n','\r','\n' ]) acc' of
          Just i -> do
            let (h, rest) = splitAt i acc'
                body0 = BSC.pack (drop 4 rest)
                contentLen = headerInt "content-length" (parseHeaders h)
            body <- if BS.length body0 >= contentLen
                      then pure body0
                      else readN c (contentLen - BS.length body0) body0
            pure (Just (BSL.fromStrict body))
          Nothing -> hdr acc'
    readN _ 0 acc = pure acc
    readN s n acc = do
      chunk <- NSB.recv s n
      if BS.null chunk then pure acc else readN s (n - BS.length chunk) (BS.append acc chunk)
    parseHeaders h = [ (map toLower (trim k), trim (drop 1 v))
                     | l <- lines h, let (k, v) = break (== ':') l, not (null v) ]
    trim = f . f where f = reverse . dropWhile (== ' ')
    headerInt k hs = maybe 0 read (lookup k hs)

findSub :: String -> String -> Maybe Int
findSub pat = go 0
  where
    go i s | prefixOf pat s = Just i
           | null s = Nothing
           | otherwise = go (i + 1) (tail s)
    prefixOf [] _ = True
    prefixOf _ [] = False
    prefixOf (a:as) (b:bs) = a == b && prefixOf as bs

sendAll' :: Socket -> BS.ByteString -> IO ()
sendAll' = NSB.sendAll

-- ---------------------------------------------------------------------------
-- drive the real Haskell RpcClient through a full explorer session
-- ---------------------------------------------------------------------------

recordSession :: MockServer -> IO [(String, BSL.ByteString, BSL.ByteString)]
recordSession mock = do
  client <- newRpcClient (mockPort mock)
  let sid = "sess-1"
  _ <- health client
  _ <- loadSpec client (LoadSpecParams (getSpecSources spec) (Just "Init") (Just "Next") ["Inv"] ["Export"])
  _ <- assumeTransition client (AssumeTransitionParams sid 0 True Nothing)
  _ <- nextStep client (NextStateParams sid)
  _ <- checkInvariant client (CheckInvariantParams sid 0 StateInvariant (Just 10))
  _ <- query client (QueryParams sid [QueryState] Nothing Nothing)
  _ <- assumeState client (AssumeStateParams sid True Nothing (M.fromList [("h", VInt 1)]))
  _ <- rollback client (RollbackParams sid 2)
  _ <- disposeSpec client (DisposeSpecParams sid)
  reverse <$> readIORef (mockLog mock)

-- ---------------------------------------------------------------------------
-- output
-- ---------------------------------------------------------------------------

main :: IO ()
main = do
  [outDir, commit] <- getArgs
  writeFile (outDir ++ "/client_messages.jsonl")
    (concatMap (\(_, m) -> BSLC.unpack (encode m) ++ "\n") clientMessages)
  writeFile (outDir ++ "/mirror_messages.jsonl")
    (concatMap (\(_, m) -> BSLC.unpack (encode m) ++ "\n") mirrorMessages)
  writeFile (outDir ++ "/manifest.json") $ BSLC.unpack $ encode $ object
    [ "client" .= [object ["line" .= (i :: Int), "ctor" .= n] | (i, (n, _)) <- zip [1 ..] clientMessages]
    , "mirror" .= [object ["line" .= (i :: Int), "ctor" .= n] | (i, (n, _)) <- zip [1 ..] mirrorMessages]
    ]
  entries <- withMockServer recordSession
  writeFile (outDir ++ "/explorer_transcripts.jsonl") $ concatMap entryLine entries
  writeFile (outDir ++ "/metadata.json") $ BSLC.unpack $ encode $ object
    [ "source" .= ("ModelMirrors (Haskell)" :: Text)
    , "commit" .= T.pack commit
    , "generated_by" .= ("tools/fixtures/GenGolden.hs" :: Text)
    , "client_ctor_count" .= (19 :: Int)
    , "mirror_ctor_count" .= (20 :: Int)
    ]
  putStrLn ("client variants: " ++ show (length clientMessages))
  putStrLn ("mirror variants: " ++ show (length mirrorMessages))
  putStrLn ("rpc transcripts: " ++ show (length entries))
  where
    entryLine (meth, req, resp) = BSLC.unpack (encode (object
      [ "method" .= T.pack meth
      , "request" .= T.pack (BSLC.unpack req)
      , "response" .= T.pack (BSLC.unpack resp)
      ])) ++ "\n"
