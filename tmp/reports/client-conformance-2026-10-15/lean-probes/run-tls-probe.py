#!/usr/bin/env python3
"""REMOTE WSL ONLY. Run already-built probe against fresh task-owned PKI/peers."""
import argparse, os, pathlib, socket, subprocess, time
p=argparse.ArgumentParser()
p.add_argument('--client-root',type=pathlib.Path,required=True)
p.add_argument('--output',type=pathlib.Path,required=True)
a=p.parse_args()
a.output.mkdir(parents=True,exist_ok=True)
pki=a.output/'pki'
subprocess.run(['bash',str(a.client_root/'server-mode/test/gen-test-certs.sh'),str(pki)],check=True,stdout=subprocess.DEVNULL)
binary=pathlib.Path(__file__).resolve().parent/'.lake/build/bin/tls-identity-probe'
for peer in ('server','server-cn'):
    with socket.socket() as sock:
        sock.bind(('127.0.0.1',0)); port=sock.getsockname()[1]
    with (a.output/(peer+'.stderr.log')).open('wb') as err:
        process=subprocess.Popen(['openssl','s_server','-quiet','-www','-Verify','1','-verify_return_error','-tls1_3',
            '-accept',f'127.0.0.1:{port}','-cert',str(pki/(peer+'.crt')),'-key',str(pki/(peer+'.key')),
            '-CAfile',str(pki/'ca.crt')],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=err)
        try:
            for _ in range(100):
                if process.poll() is not None: raise RuntimeError('TLS peer exited before readiness')
                try:
                    with socket.create_connection(('127.0.0.1',port),timeout=.1): break
                except OSError: time.sleep(.05)
            else: raise RuntimeError('TLS peer readiness deadline exceeded')
            result=subprocess.run([str(binary),str(pki),str(port),peer],check=True,capture_output=True,text=True,timeout=45)
            (a.output/(peer+'.jsonl')).write_text(result.stdout)
            (a.output/(peer+'.client.stderr.log')).write_text(result.stderr)
            print(result.stdout,end='')
        finally:
            process.terminate()
            try: process.wait(timeout=3)
            except subprocess.TimeoutExpired: process.kill(); process.wait(timeout=3)
