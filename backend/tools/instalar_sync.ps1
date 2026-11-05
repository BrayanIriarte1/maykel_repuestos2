# Crea (o reemplaza) la tarea programada de Windows que sincroniza el inventario con el
# sistema del cliente cada 30 minutos.
#
# Uso (PowerShell, desde la carpeta backend):
#   powershell -ExecutionPolicy Bypass -File tools\instalar_sync.ps1
#   powershell -ExecutionPolicy Bypass -File tools\instalar_sync.ps1 -Minutos 15
#   powershell -ExecutionPolicy Bypass -File tools\instalar_sync.ps1 -Quitar     # desinstala
param(
    [int]$Minutos = 30,
    [string]$Nombre = 'MaykelRepuestos-Sync',
    [switch]$Quitar
)
$ErrorActionPreference = 'Stop'

if ($Quitar) {
    Unregister-ScheduledTask -TaskName $Nombre -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Tarea '$Nombre' eliminada."
    return
}

$script = Join-Path $PSScriptRoot 'sync_programado.ps1'
$accion = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`""
$inicio = (Get-Date).AddMinutes(1)
$disparador = New-ScheduledTaskTrigger -Once -At $inicio -RepetitionInterval (New-TimeSpan -Minutes $Minutos)
$ajustes = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 20)

Register-ScheduledTask -TaskName $Nombre -Action $accion -Trigger $disparador -Settings $ajustes `
    -Description "Sincroniza el inventario de Maykel Repuestos cada $Minutos min" -Force | Out-Null
Write-Host "Listo: la tarea '$Nombre' correra cada $Minutos minutos (primera vez: $($inicio.ToString('HH:mm')))."
Write-Host "Resultado de cada corrida: backend\logs\sync.log"
