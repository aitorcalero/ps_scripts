$RunKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"

# 1) Backup a .reg en Documentos (con timestamp)
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$backup = Join-Path $env:USERPROFILE "Documents\RunKey-Backup-$ts.reg"
reg.exe export "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" "$backup" /y | Out-Null
Write-Host "Backup creado: $backup"

# 2) Entradas a eliminar (ajusta si quieres)
$Remove = @(
  "BingSvc",
  "Docker Desktop",
  "DuetDisplay",
  "ZoomIt",
  "electron.app.LM Studio",
  "com.squirrel.Teams.Teams",
  "Surfshark",
  "Microsoft.Lists",
  "Adobe Acrobat Synchronizer"	
)

# 3) Borrado (solo si existe)
foreach ($name in $Remove) {
  if (Get-ItemProperty -Path $RunKey -Name $name -ErrorAction SilentlyContinue) {
    Remove-ItemProperty -Path $RunKey -Name $name -ErrorAction Stop
    Write-Host "Eliminado: $name"
  } else {
    Write-Host "No existe: $name"
  }
}

# 4) Mostrar estado final
Write-Host "`nEstado final:"
Get-ItemProperty $RunKey |
  Select-Object * -ExcludeProperty PSPath,PSParentPath,PSChildName,PSDrive,PSProvider |
  Format-List