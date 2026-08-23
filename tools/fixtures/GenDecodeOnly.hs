{-# LANGUAGE OverloadedStrings #-}
-- | Decode-only fixture generator for the JS-client wire shape (t17):
-- MirrorECMA omits optional keys where the Haskell clients send explicit
-- nulls. Each candidate line on stdin is decoded with the pinned Haskell
-- FromJSON instances and re-encoded with ToJSON; the pair is emitted as a
-- {"json":..,"expect":"ok:<re-encode>"} decode_only.jsonl entry, so the
-- Lean decode path is pinned to the same semantics (absent == null, plus
-- the Apalache/Types.hs defaults).
module Main (main) where

import qualified Data.ByteString.Lazy.Char8 as BSLC
import Data.Aeson (eitherDecode, encode, ToJSON, FromJSON, object, (.=))
import qualified Data.Aeson as A
import System.IO

import Protocol.Core
import Protocol.Format.Json ()

emit :: String -> IO ()
emit raw = do
  case eitherDecode (BSLC.pack raw) of
    Left err -> hPutStrLn stderr ("SKIP (decode error): " ++ err)
    Right m -> do
      let _ = m :: ClientMessage
      let re = BSLC.unpack (encode m)
          entry = encode (object ["json" .= raw, "expect" .= ("ok:" ++ re)])
      BSLC.putStrLn entry

main :: IO ()
main = do
  raws <- lines <$> getContents
  mapM_ emit raws
