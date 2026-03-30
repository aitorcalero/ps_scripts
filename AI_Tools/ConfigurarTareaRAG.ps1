# Definir rutas
$scriptPath = "$HOME\Documents\GeminiCLI\indexador.py"
$pythonExe = "python.exe" # Asegúrate de que python esté en tu PATH

# 1. Crear la acción: Ejecutar el indexador en segundo plano
$action = New-ScheduledTaskAction -Execute $pythonExe -Argument $scriptPath

# 2. Crear el disparador: Semanal, los lunes a las 9:00 AM
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 9am

# 3. Configuraciones adicionales (ejecutar aunque no esté conectado a la corriente)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

# 4. Registrar la tarea
Register-ScheduledTask -TaskName "Gemini_RAG_Indexer_Semanal" `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Description "Indexa los logs de Gemini para el sistema RAG local." `
    -Force

Write-Host "✔ Tarea programada creada: El indexador se ejecutará cada lunes a las 9:00 AM." -ForegroundColor Green