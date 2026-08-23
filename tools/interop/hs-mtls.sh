#!/usr/bin/env bash
set -u
cd /home/nzsn/Repos/Mirrors
D=.golden-build/mtls
rm -rf "$D" && mkdir -p "$D"
cd "$D"
openssl req -x509 -newkey rsa:2048 -keyout ca.key -out ca.crt -days 30 -nodes -subj "/CN=Interop CA" 2>/dev/null
printf 'subjectAltName=IP:127.0.0.1\nbasicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n' > server.ext
openssl req -newkey rsa:2048 -keyout server.key -out server.csr -nodes -subj "/CN=127.0.0.1" 2>/dev/null
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 30 -extfile server.ext 2>/dev/null
printf 'basicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=clientAuth\n' > client.ext
openssl req -newkey rsa:2048 -keyout client.key -out client.csr -nodes -subj "/CN=interop-client" 2>/dev/null
openssl x509 -req -in client.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out client.crt -days 30 -extfile client.ext 2>/dev/null
chmod 600 ca.key server.key client.key
# rogue PKI for negatives
openssl req -x509 -newkey rsa:2048 -keyout rogue-ca.key -out rogue-ca.crt -days 30 -nodes -subj "/CN=Rogue CA" 2>/dev/null
openssl req -newkey rsa:2048 -keyout rogue-client.key -out rogue-client.csr -nodes -subj "/CN=rogue" 2>/dev/null
openssl x509 -req -in rogue-client.csr -CA rogue-ca.crt -CAkey rogue-ca.key -CAcreateserial -out rogue-client.crt -days 30 -extfile client.ext 2>/dev/null
chmod 600 rogue-ca.key rogue-client.key
FP=$(openssl x509 -in server.crt -outform DER | openssl dgst -sha256 | awk '{print $2}')
echo "server fingerprint: $FP"
HS=/home/nzsn/Repos/ModelMirros/dist-newstyle/build/x86_64-linux/ghc-9.14.1/ModelMirrors-0.1.1.0/x/ModelMirrors/build/ModelMirrors/ModelMirrors
cd /home/nzsn/Repos/Mirrors
PORT=$((31000 + RANDOM % 4000))
.lake/build/bin/mirror --server "$PORT" --tls --cert "$D/server.crt" --key "$D/server.key" --ca "$D/ca.crt" &
SRV=$!
trap 'kill $SRV 2>/dev/null || true' EXIT
for i in $(seq 1 50); do (echo > /dev/tcp/127.0.0.1/$PORT) 2>/dev/null && break; sleep 0.2; done

echo "== Haskell validate over mTLS (pinned) =="
LC_ALL=C.UTF-8 timeout 240 "$HS" validate --host 127.0.0.1 --port "$PORT" --tls \
  --cert "$D/client.crt" --key "$D/client.key" --ca "$D/ca.crt" --pin "$FP" \
  --spec .golden-build/specs/HourClock.tla --inv Inv --bound 10
echo "POSITIVE_RC=$?"

echo "== negative: wrong pin =="
LC_ALL=C.UTF-8 timeout 60 "$HS" validate --host 127.0.0.1 --port "$PORT" --tls \
  --cert "$D/client.crt" --key "$D/client.key" --ca "$D/ca.crt" --pin 0000000000000000000000000000000000000000000000000000000000000000 \
  --spec .golden-build/specs/HourClock.tla --inv Inv --bound 10
echo "WRONGPIN_RC=$?"

echo "== negative: rogue client cert =="
LC_ALL=C.UTF-8 timeout 60 "$HS" validate --host 127.0.0.1 --port "$PORT" --tls \
  --cert "$D/rogue-client.crt" --key "$D/rogue-client.key" --ca "$D/ca.crt" \
  --spec .golden-build/specs/HourClock.tla --inv Inv --bound 10
echo "ROGUE_RC=$?"

kill $SRV 2>/dev/null
