module Main where
import Control.Exception (SomeException,try)
import Data.Aeson qualified as A
import Data.ByteString qualified as BS
import Data.IORef
import Data.Text qualified as T
import Protocol.Transport.Core
newtype Capture = Capture (IORef [BS.ByteString])
instance Transport Capture where
 send (Capture ref) b = modifyIORef' ref (++[b])
 recv _ = pure BS.empty
main :: IO ()
main = do
 ref <- newIORef []
 normal <- try (sendMsg (Capture ref) (T.pack "normal")) :: IO (Either SomeException ())
 writes <- readIORef ref
 print ("normal",either (const False) (const True) normal, map BS.length writes)
 writeIORef ref []
 oversize <- try (sendMsg (Capture ref) (T.replicate 65534 (T.singleton 'x'))) :: IO (Either SomeException ())
 bad <- readIORef ref
 print ("oversize",either (const "refused") (const "accepted") oversize, map BS.length bad)
 if normal `isSuccess` writes && either (const True) (const False) oversize && null bad
  then putStrLn "FIXED_ZERO_WRITE_REFUSAL" else putStrLn "BASELINE_OVERSIZE_WRITE_CONFIRMED"
 where isSuccess (Right ()) xs = not (null xs)
       isSuccess _ _ = False
