# ============================================================
# ahk_migrate.ps1 - Migración y configuración de AHK v2
# ============================================================

# 1. Definir rutas
$rutaOriginal  = "C:\Users\aitor.calero\iCloudDrive_Backup_20260317_171604\AHK\Abreviaturas.ahk"
$rutaDestino   = "C:\Users\aitor.calero\iCloudDrive\02_Profesional_y_Proyectos\Proyectos_Desarrollo\AHK\Abreviaturas.ahk"
$carpetaDestino = Split-Path $rutaDestino

# 2. Asegurar que la carpeta de destino existe
if (-not (Test-Path $carpetaDestino)) {
    New-Item -ItemType Directory -Path $carpetaDestino -Force | Out-Null
    Write-Host "[OK] Carpeta de destino creada: $carpetaDestino" -ForegroundColor Green
} else {
    Write-Host "[OK] Carpeta de destino ya existe: $carpetaDestino" -ForegroundColor Green
}

# 3. Copiar el script a la ubicación definitiva
if (Test-Path $rutaOriginal) {
    Copy-Item -Path $rutaOriginal -Destination $rutaDestino -Force
    Write-Host "[OK] Script copiado a la ubicación definitiva." -ForegroundColor Green
} elseif (Test-Path $rutaDestino) {
    Write-Host "[INFO] El script ya existe en el destino (no había copia en backup). Se continúa con la ruta existente." -ForegroundColor Yellow
} else {
    Write-Host "[ERROR] No se encontró Abreviaturas.ahk ni en backup ni en destino. Revisa las rutas." -ForegroundColor Red
    exit 1
}

# 4. Limpiar el autoarranque roto en el registro
$regPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
if ((Get-ItemProperty -Path $regPath -Name "AutoHotKey" -ErrorAction SilentlyContinue) -ne $null) {
    Remove-ItemProperty -Path $regPath -Name "AutoHotKey" -Force
    Write-Host "[OK] Entrada obsoleta 'AutoHotKey' eliminada del registro (HKCU\Run)." -ForegroundColor Green
} else {
    Write-Host "[INFO] No se encontró entrada 'AutoHotKey' en el registro. Nada que limpiar." -ForegroundColor Yellow
}

# 5. Crear nuevo autoarranque limpio mediante acceso directo en Startup
$startupFolder = [System.Environment]::GetFolderPath('Startup')
$shortcutPath  = Join-Path $startupFolder "Abreviaturas_AHK.lnk"
$wshShell      = New-Object -ComObject WScript.Shell
$shortcut      = $wshShell.CreateShortcut($shortcutPath)
$shortcut.TargetPath       = $rutaDestino
$shortcut.WorkingDirectory = $carpetaDestino
$shortcut.Description      = "Autoarranque de Abreviaturas AHK v2"
$shortcut.Save()
Write-Host "[OK] Acceso directo de autoarranque creado en: $shortcutPath" -ForegroundColor Green

# 6. Verificar si hay restos de AHK v1 instalados via winget
Write-Host ""
Write-Host "[INFO] Verificando instalaciones de AHK via winget..." -ForegroundColor Cyan
winget list --name 'AutoHotkey' 2>&1

Write-Host ""
Write-Host "=== PROCESO COMPLETADO ===" -ForegroundColor Cyan
Write-Host "Script activo en: $rutaDestino"
Write-Host "Autoarranque configurado en: $shortcutPath"
Write-Host "Reinicia sesion o ejecuta el script manualmente para verificar."
