import ctypes
import json
from pathlib import Path
import shutil
import tempfile
root=Path('/mnt/d/Desktop/Workspaces/Mirrors-DPM-remediation-20261013/build')
directory=Path(tempfile.mkdtemp(prefix='owned-placement-probe-',dir=root))
try:
    source=directory/'source';source.mkdir();(source/'data').write_text('probe')
    destination=directory/'destination'
    libc=ctypes.CDLL(None,use_errno=True)
    result=libc.renameat2(-100,str(source).encode(),-100,str(destination).encode(),1)
    error=ctypes.get_errno() if result else None
    record={'schema':'mirrors.dpm-output-placement/v1','root':str(root),
            'atomicNoReplaceSupported':result==0,'errno':error}
    (root/'output-placement.json').write_text(json.dumps(record,indent=2)+'\n')
    print(json.dumps(record))
finally:shutil.rmtree(directory)
