from common import *
def main():
 for script in ['collect-replays.py','collect-linked.py','collect-reductions.py','qualify-rc11.py','run-independent-q2.py']:
  run('rc11-pipeline-'+script.removesuffix('.py'),['python3',PLAN/script],env=environment(),timeout=3600)
 print('RC11 LINKED QUALIFICATION AND INDEPENDENT Q2 GREEN',flush=True)
if __name__=='__main__':main()
