Write-Host '=== Existe AutoHotKey.ps1 en iCloud Drive ===' -ForegroundColor Cyan
$ps1path = 'C:\Users\aitor.calero\iCloud Drive\AHK\AutoHotKey.ps1'
Test-Path $ps1path

Write-Host ''
Write-Host '=== Contenido si existe ===' -ForegroundColor Cyan
if (Test-Path $ps1path) { Get-Content $ps1path }

Write-Host ''
Write-Host '=== Listar carpeta iCloud Drive\AHK ===' -ForegroundColor Cyan
Get-ChildItem 'C:\Users\aitor.calero\iCloud Drive\AHK' -ErrorAction SilentlyContinue | Format-Table Name,FullName,LastWriteTime -AutoSize

Write-Host ''
Write-Host '=== Listar carpeta iCloudDrive\02_Profesional...\AHK ===' -ForegroundColor Cyan
Get-ChildItem 'C:\Users\aitor.calero\iCloudDrive\02_Profesional_y_Proyectos\Proyectos_Desarrollo\AHK' -ErrorAction SilentlyContinue | Format-Table Name,FullName,LastWriteTime -AutoSize
