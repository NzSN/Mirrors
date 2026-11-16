"""Read only the owned native build/test progress logs."""
from common import *


def main():
    script = r'''
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$stage='D:\ModelMirrors\staging\completion-rc12-20261116'
$logs=@()
foreach($name in @('rc12-clean-build','rc12-clean-full-test')) {
 $path=$stage+'\'+$name+'.log'
 if(Test-Path -LiteralPath $path) {
  $item=Get-Item -LiteralPath $path
  $logs+=@(@{name=$name;bytes=$item.Length;lastWriteUtc=$item.LastWriteTimeUtc.ToString('o');tail=@(Get-Content -LiteralPath $path -Tail 12 | ForEach-Object {$_.ToString()})})
 }
}
[ordered]@{observedAt=[DateTime]::UtcNow.ToString('o');logs=$logs}|ConvertTo-Json -Depth 5
'''
    name = 'native-progress-' + datetime.now(timezone.utc).strftime('%H%M%S')
    value = json.loads(remote(name, script, timeout=60))
    print(json.dumps(value, indent=2), flush=True)


if __name__ == '__main__':
    main()
