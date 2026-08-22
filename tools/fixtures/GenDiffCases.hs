{-# LANGUAGE OverloadedStrings #-}
-- | Differential-test case generator (design doc §8 Phase 1 exit criterion).
--
--   Generates QuickCheck pairs of state valuations (Map Text Value), runs the
--   *Haskell* Engine.Core.diffState on each pair, and emits one JSON line per
--   case:
--     {"expected": <Map JSON>, "actual": <Map JSON>,
--      "haskell": {"tag":"match"} | {"tag":"mismatch","hints":[DiffHint JSON]},
--      "hintCount": N}
--
--   Deterministic: fixed QCGen seed, so the corpus is reproducible and can be
--   checked in. Consumed by tools/DiffCross.lean (Lean side of the
--   differential test). ModelMirrors is consumed read-only as a pinned
--   external artifact.
module Main (main) where

import Control.Monad (replicateM)
import qualified Data.Aeson as A
import Data.Aeson (object, (.=))
import qualified Data.ByteString.Lazy.Char8 as BSLC
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text as T
import System.Environment (getArgs)
import System.IO

import Apalache.Types
import Engine.Core
import Engine.Types
import Protocol.Format.Json ()  -- aeson instances for DiffHint
import Test.QuickCheck (Gen, vectorOf, frequency, choose, elements, oneof)
import qualified Test.QuickCheck.Gen as G
import Test.QuickCheck.Random (mkQCGen)

keys :: [Text]
keys = map T.pack ["a", "b", "c", "d", "e", "f", "h", "n", "ok", "s", "z", "#meta", "action_taken", "parameters"]

-- | Structured values over all constructors, depth-bounded by the size
--   parameter; sets may contain duplicate elements (representation-level
--   reality the diff engine must handle).
genValue :: Int -> Gen Value
genValue 0 = oneof [ VInt <$> genInt, VBool <$> elements [True, False]
                   , VStr <$> genStr, pure VNull
                   , VUnserializable <$> elements ["SetOfSets", "Fun"] ]
genValue d = frequency
  [ (3, genValue 0)
  , (2, VSet <$> vectorOf 2 (genValue (d - 1)))
  , (2, VSeq <$> vectorOf 2 (genValue (d - 1)))
  , (2, VTuple <$> vectorOf 3 (genValue (d - 1)))
  , (3, VRecord . M.fromList <$> genBindings (d - 1))
  , (2, VMap . M.fromList . map (\k -> (k, VInt 1)) <$> vectorOf 2 (elements ["1", "2", "x"]))
  , (2, VVariant <$> elements ["Some", "None"] <*> genValue (d - 1))
  ]
  where genBindings d' = do
          n <- choose (1, 3)
          ks <- vectorOf n (elements ["p", "q", "r", "s"])
          vs <- vectorOf n (genValue d')
          pure (zip ks vs)

genInt :: Gen Integer
genInt = frequency
  [ (3, fromIntegral <$> (choose (-5, 5) :: Gen Int))
  , (1, fromIntegral <$> (choose (-1000000000, 1000000000) :: Gen Int))
  ]

genStr :: Gen Text
genStr = elements ["tick", "Init", "Next", "reset", "x", "zz", T.pack "ünïcode"]

-- | A state valuation: distinct keys (Map), values of bounded size.
genState :: Gen (Map Text Value)
genState = do
  n <- choose (0, 6)
  ks <- vectorOf n (elements keys)
  vs <- mapM (\k -> genValue 3) ks
  pure (M.fromList (zip ks vs))

-- | Pair (expected, actual) built from a shared base so diffs are realistic:
--   dropped keys, added keys, mutated values, plus fully independent pairs.
genCase :: Gen (Map Text Value, Map Text Value)
genCase = do
  base <- genState
  mode <- elements [0 .. 4 :: Int]
  case mode of
    0 -> pure (base, base)                                    -- equal
    1 -> pure (base, M.filterWithKey (\k _ -> notElem k droppedKeys) base)
    2 -> do extra <- genState; pure (base, M.union base extra)
    3 -> do mutated <- mapM mutate (M.toList base); pure (base, M.fromList mutated)
    _ -> do a <- genState; b <- genState; pure (a, b)          -- independent
  where
    droppedKeys = map T.pack ["a", "s", "z"]
    mutate (k, v) = do
      v' <- genValue 3
      pure (k, if even (T.length k) then v' else v)

renderCase :: (Map Text Value, Map Text Value) -> A.Value
renderCase (e, a) =
  let d = diffState e a
      (tag, hints) = case d of
        StatesMatch -> ("match" :: Text, [] :: [DiffHint])
        StateMismatch _ _ hs -> ("mismatch", hs)
  in object
       [ "expected" .= e
       , "actual" .= a
       , "haskell" .= object
           ([ "tag" .= tag ] ++
            [ "hints" .= hints | tag == "mismatch" ])
       , "hintCount" .= length hints
       ]

main :: IO ()
main = do
  [outPath, nStr] <- getArgs
  let n = read nStr :: Int
      gen = vectorOf n genCase
      cases = G.unGen gen (mkQCGen 20260822) 100000
  withFile outPath WriteMode $ \h ->
    mapM_ (BSLC.hPutStrLn h . A.encode . renderCase) cases
  putStrLn ("generated " ++ show n ++ " differential cases -> " ++ outPath)
