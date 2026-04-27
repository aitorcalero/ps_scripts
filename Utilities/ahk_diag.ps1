Write-Host '=== AHK instalado (winget) ===' -ForegroundColor Cyan
winget list --name 'AutoHotkey' 2>&1

Write-Host ''
Write-Host '=== AHK instalado (registro) ===' -ForegroundColor Cyan
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like '*AutoHotkey*' } |
    Select-Object DisplayName,DisplayVersion,InstallLocation |
    Format-Table -AutoSize

Write-Host ''
Write-Host '=== Autoarranque (registro HKCU Run) ===' -ForegroundColor Cyan
Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue | Format-List

Write-Host ''
Write-Host '=== Autoarranque (carpeta Startup) ===' -ForegroundColor Cyan
Get-ChildItem ([System.Environment]::GetFolderPath('Startup')) -ErrorAction SilentlyContinue | Format-Table Name,FullName -AutoSize

Write-Host ''
Write-Host '=== Buscar Abreviaturas.ahk en disco ===' -ForegroundColor Cyan
Get-ChildItem -Path 'C:\Users\aitor.calero' -Filter 'Abreviaturas.ahk' -Recurse -ErrorAction SilentlyContinue |
    Select-Object FullName,LastWriteTime |
    Format-Table -AutoSize
