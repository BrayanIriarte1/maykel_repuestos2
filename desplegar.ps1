<#
 Despliega a producción (VPS de MOX) desde este PC.
   .\desplegar.ps1            -> web + backend
   .\desplegar.ps1 -Web       -> solo el frontend (pantallas, textos, estilos)
   .\desplegar.ps1 -Backend   -> solo el servidor/API (reinicia el servicio)
 Requisitos: Flutter y Dart en el PATH y la llave SSH ~/.ssh/maykel_vps.
 Guía completa: docs/DESPLIEGUE.md
#>
param(
    [switch]$Web,
    [switch]$Backend,
    [string]$Servidor = 'root@179.61.200.126',
    [string]$Llave = "$env:USERPROFILE\.ssh\maykel_vps",
    [string]$Url = 'https://maykel-repuestos2.cl'
)
$ErrorActionPreference = 'Stop'
if (-not $Web -and -not $Backend) { $Web = $true; $Backend = $true }
$raiz = $PSScriptRoot
$tmp = Join-Path $env:TEMP 'maykel_deploy'
New-Item -ItemType Directory -Force $tmp | Out-Null

function Ejecutar($etiqueta, [scriptblock]$bloque) {
    Write-Host "==> $etiqueta" -ForegroundColor Cyan
    & $bloque
    if ($LASTEXITCODE -ne 0) { throw "Fallo: $etiqueta (codigo $LASTEXITCODE)" }
}
function Remoto($comando) { ssh -i $Llave -o BatchMode=yes $Servidor $comando }
function Subir($origen, $destino) { scp -q -i $Llave -o BatchMode=yes $origen "${Servidor}:$destino" }

if ($Web) {
    Ejecutar 'Compilando la web (Flutter)' {
        Push-Location "$raiz\app"; flutter build web --release --no-web-resources-cdn; Pop-Location
    }
    Ejecutar 'Empaquetando la web' { tar -czf "$tmp\web.tar.gz" -C "$raiz\app\build" web }
    Ejecutar 'Subiendo la web' { Subir "$tmp\web.tar.gz" '/root/web.tar.gz' }
    Ejecutar 'Instalando la web en el servidor' {
        Remoto 'rm -rf /opt/maykel/app/build/web && tar -xzf /root/web.tar.gz -C /opt/maykel/app/build && rm /root/web.tar.gz'
    }
}

if ($Backend) {
    Ejecutar 'Compilando el servidor para Linux' {
        Push-Location "$raiz\backend"
        dart pub get
        dart compile exe --target-os linux --target-arch x64 bin/server.dart -o "$tmp\server"
        if ($LASTEXITCODE -eq 0) { dart compile exe --target-os linux --target-arch x64 tools/sync_agent.dart -o "$tmp\sync_agent" }
        $codigo = $LASTEXITCODE
        Pop-Location
        $global:LASTEXITCODE = $codigo
    }
    Ejecutar 'Subiendo binarios, migraciones, fuentes y documentacion' {
        Remoto 'mkdir -p /opt/maykel/backend/{bin,tools,docs,database,assets/fonts}'
        Subir "$tmp\server" '/opt/maykel/backend/bin/server.nuevo'
        Subir "$tmp\sync_agent" '/opt/maykel/backend/tools/sync_agent.nuevo'
        Subir "$raiz\backend\database\schema.sql" '/opt/maykel/backend/database/'
        Subir "$raiz\backend\database\migraciones.sql" '/opt/maykel/backend/database/'
        Subir "$raiz\backend\docs\openapi.yaml" '/opt/maykel/backend/docs/'
        scp -q -i $Llave -o BatchMode=yes "$raiz\backend\assets\fonts\*" "${Servidor}:/opt/maykel/backend/assets/fonts/"
    }
    Ejecutar 'Reiniciando el servicio' {
        Remoto 'cd /opt/maykel/backend && chmod +x bin/server.nuevo tools/sync_agent.nuevo && mv bin/server.nuevo bin/server && mv tools/sync_agent.nuevo tools/sync_agent && systemctl restart maykel && sleep 4 && systemctl is-active maykel'
    }
}

Write-Host "==> Verificando $Url" -ForegroundColor Cyan
Start-Sleep 2
$salud = Invoke-RestMethod "$Url/api/health"
Write-Host ("Estado: {0} | ultima sincronizacion: {1}" -f $salud.status, $salud.ultima_sincronizacion) -ForegroundColor Green
Write-Host 'Listo. Recarga la página con Ctrl+F5.' -ForegroundColor Green
