"""Keep the owned Windows oracle monitor attached until guarded shutdown."""
from common import *

run('owned-oracle-session', SSH + ['powershell', '-NoProfile', '-NonInteractive',
    '-ExecutionPolicy', 'Bypass', '-File', STAGE.replace('\\', '/') + '/windows-oracle.ps1'], timeout=7200)
