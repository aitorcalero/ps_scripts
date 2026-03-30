$ScriptPath = "C:\Users\aitor.calero\OneDrive - ESRI ESPAÑA Soluciones Geoespaciales S.L\7_CODE\PS_Scripts\Organizar-Escritorio.ps1"
$Trigger = New-ScheduledTaskTrigger -AtLogOn
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File" $ScriptPath
Register-ScheduledTask -TaskName "OrganizarEscritorio" -Trigger $Trigger -Action $Action -Description "Organiza el escritorio al iniciar sesión" -User $env:USERNAME
