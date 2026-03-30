$script   = "C:\Users\aitor.calero\OneDrive - ESRI ESPAÑA Soluciones Geoespaciales S.L\7_CODE\PS_Scripts\Organizar-Descargas.ps1"

$action   = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$script`""

# Ejemplo: los lunes a las 09:00, cada 1 semana
$trigger  = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 09:00

# Settings: StartWhenAvailable = “ejecutar lo antes posible si se perdió”
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable `
            -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest

Register-ScheduledTask -TaskName "OrganizarDescargas_Semanal" `
  -TaskPath "\PowerShellForge\" -Action $action -Trigger $trigger `
  -Principal $principal -Settings $settings `
  -Description "Organiza Descargas semanal; si se pierde la hora, se ejecuta al encender"
