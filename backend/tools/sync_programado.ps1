$ErrorActionPreference = 'Continue'
$backend = Split-Path -Parent $PSScriptRoot
$env:Path = "C:\Users\chunc\flutter\bin;C:\Users\chunc\flutter\bin\cache\dart-sdk\bin;" + $env:Path
Set-Location $backend
New-Item -ItemType Directory -Force -Path "$backend\logs" | Out-Null
$log = "$backend\logs\sync.log"
"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Inicio sync" | Add-Content $log
dart run tools\sync_agent.dart --sistema 2>&1 | Add-Content $log
"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Fin sync" | Add-Content $log
