# Respaldo de la base de datos + fotos de productos.
# Uso (desde backend/):  powershell -File tools\respaldo.ps1
# Lee DB_* desde .env, guarda en backend\respaldos\ y conserva los ultimos 14.
$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
Set-Location $raiz

$cfg = @{}
Get-Content .env | Where-Object { $_ -match '^\s*[A-Z_]+=' } | ForEach-Object {
    $k, $v = $_ -split '=', 2
    $cfg[$k.Trim()] = $v.Trim()
}

$pgDump = (Get-Command pg_dump -ErrorAction SilentlyContinue).Source
if (-not $pgDump) { $pgDump = Get-ChildItem 'C:\Program Files\PostgreSQL\*\bin\pg_dump.exe' | Select-Object -Last 1 -ExpandProperty FullName }

New-Item -ItemType Directory -Force respaldos | Out-Null
$fecha = Get-Date -Format 'yyyy-MM-dd_HHmm'
$archivo = "respaldos\bd_$fecha.dump"

$env:PGPASSWORD = $cfg['DB_PASS']
& $pgDump -h $cfg['DB_HOST'] -p $cfg['DB_PORT'] -U $cfg['DB_USER'] -F c -f $archivo $cfg['DB_NAME']
if ($LASTEXITCODE -ne 0) { throw 'pg_dump fallo' }

if (Test-Path uploads) { Compress-Archive -Path uploads -DestinationPath "respaldos\fotos_$fecha.zip" -Force }

Get-ChildItem respaldos\bd_*.dump | Sort-Object LastWriteTime -Descending | Select-Object -Skip 14 | Remove-Item
Get-ChildItem respaldos\fotos_*.zip | Sort-Object LastWriteTime -Descending | Select-Object -Skip 14 | Remove-Item
Write-Host "Respaldo listo: $archivo ($([math]::Round((Get-Item $archivo).Length/1MB,1)) MB)"

# Para restaurar:  pg_restore -h localhost -U postgres -d maykel_repuestos2 --clean --if-exists respaldos\bd_<fecha>.dump
