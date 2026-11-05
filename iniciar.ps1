# Inicia la pagina completa (API + sitio web) en http://localhost:8080
# Uso (PowerShell, desde la carpeta del proyecto):
#   powershell -ExecutionPolicy Bypass -File iniciar.ps1
#   powershell -ExecutionPolicy Bypass -File iniciar.ps1 -Compilar     # recompila la web antes
param([switch]$Compilar)

$raiz = $PSScriptRoot
foreach ($c in @("$env:USERPROFILE\flutter\bin", 'C:\flutter\bin', 'C:\src\flutter\bin')) {
    if ((Test-Path "$c\flutter.bat") -and -not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        $env:Path = "$c;$c\cache\dart-sdk\bin;" + $env:Path
    }
}
foreach ($cmd in 'dart', 'flutter') {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Host "No se encontro '$cmd'. Instala Flutter y agregalo al PATH (ver docs\GUIA_OTRO_PC.md, paso 2)." -ForegroundColor Red
        return
    }
}
if (-not (Test-Path "$raiz\backend\.env")) {
    Write-Host "Falta backend\.env. Copia backend\.env.example como backend\.env y completalo (docs\GUIA_OTRO_PC.md, paso 5)." -ForegroundColor Red
    return
}

if ($Compilar -or -not (Test-Path "$raiz\app\build\web\index.html")) {
    Write-Host 'Compilando la web (tarda 1-3 minutos)...' -ForegroundColor Yellow
    Push-Location "$raiz\app"
    flutter pub get
    flutter build web --no-web-resources-cdn
    Pop-Location
}

Push-Location "$raiz\backend"
dart pub get | Out-Null
Write-Host 'Servidor en http://localhost:8080  (Ctrl+C para detenerlo)' -ForegroundColor Green
dart run bin/server.dart
Pop-Location
