# ============================================================
# ahk_verify.ps1 - Verificación post-migración AHK
# ============================================================

Write-Host "=== 1. Script en ubicacion definitiva ===" -ForegroundColor Cyan
$rutaDestino = "C:\Users\aitor.calero\iCloudDrive\02_Profesional_y_Proyectos\Proyectos_Desarrollo\AHK\Abreviaturas.ahk"
if (Test-Path $rutaDestino) {
    Get-Item $rutaDestino | Select-Object FullName, LastWriteTime, Length | Format-List
} else {
    Write-Host "[ERROR] No encontrado." -ForegroundColor Red
}

Write-Host "=== 2. Registro HKCU\Run (no debe haber entrada AutoHotKey rota) ===" -ForegroundColor Cyan
Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue |
    Select-Object -Property * -ExcludeProperty PS* | Format-List

Write-Host "=== 3. Acceso directo en Startup ===" -ForegroundColor Cyan
$startupFolder = [System.Environment]::GetFolderPath('Startup')
Get-ChildItem $startupFolder | Format-Table Name, FullName -AutoSize

Write-Host "=== 4. AHK instalado (winget) ===" -ForegroundColor Cyan
winget list --name 'AutoHotkey' 2>&1
