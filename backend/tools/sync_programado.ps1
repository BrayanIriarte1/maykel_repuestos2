# Ejecuta UNA sincronizacion con el sistema del cliente y deja el resultado en backend\logs\sync.log.
# Lo llama la tarea programada (ver tools\instalar_sync.ps1). Funciona en cualquier PC con Dart en el PATH.
$ErrorActionPreference = 'Continue'
$backend = Split-Path -Parent $PSScriptRoot

# Si "dart" no esta en el PATH, intenta las ubicaciones habituales de Flutter.
if (-not (Get-Command dart -ErrorAction SilentlyContinue)) {
    $candidatos = @("$env:USERPROFILE\flutter\bin", 'C:\flutter\bin', 'C:\src\flutter\bin', 'C:\tools\flutter\bin')
    foreach ($c in $candidatos) {
        if (Test-Path "$c\dart.bat") { $env:Path = "$c;$c\cache\dart-sdk\bin;" + $env:Path; break }
    }
}

Set-Location $backend
New-Item -ItemType Directory -Force -Path "$backend\logs" | Out-Null
$log = "$backend\logs\sync.log"
"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Inicio sync" | Add-Content $log
dart run tools\sync_agent.dart --sistema 2>&1 | Add-Content $log
"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Fin sync" | Add-Content $log
