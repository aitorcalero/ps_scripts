$ahkBase = "C:\Users\aitor.calero\iCloudDrive\02_Profesional_y_Proyectos\Proyectos_Desarrollo\AHK"

Write-Host "=== FICHEROS EXISTENTES ===" -ForegroundColor Cyan
Get-ChildItem $ahkBase -Recurse -File | Select-Object FullName, LastWriteTime, Length | Format-Table -AutoSize

foreach ($file in (Get-ChildItem $ahkBase -Recurse -Filter "*.ahk" | Where-Object { $_.Name -notlike "*.bak*" })) {
    Write-Host ""
    Write-Host ("=== " + $file.FullName + " ===") -ForegroundColor Yellow
    Get-Content $file.FullName -Encoding UTF8
}
