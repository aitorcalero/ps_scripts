# Fix-Duet-AppleUSB-winget-logged.ps1
# Arreglo detección USB iPad para Duet con winget + pnputil + log detallado

# ========== 0) Auto-elevación a Administrador ==========
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo "powershell"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $psi.Verb = "runas"
    [System.Diagnostics.Process]::Start($psi) | Out-Null
    exit
}

# ========== 1) Setup de logging ==========
$ErrorActionPreference = 'Stop'
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile   = Join-Path $env:USERPROFILE "Desktop\FixDuet_$timestamp.log"
$global:HadErrors = $false

function Write-Log {
    param(
        [Parameter(Mandatory)][ValidateSet('INFO','OK','WARN','ERR')]
        [string]$Level,
        [Parameter(Mandatory)][string]$Message
    )
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[{0}] [{1}] {2}" -f $ts, $Level, $Message
    Add-Content -Path $LogFile -Value $line
    switch ($Level) {
        'INFO' { Write-Host $line -ForegroundColor Cyan }
        'OK'   { Write-Host $line -ForegroundColor Green }
        'WARN' { Write-Host $line -ForegroundColor Yellow }
        'ERR'  { Write-Host $line -ForegroundColor Red }
    }
    if ($Level -eq 'ERR') { $global:HadErrors = $true }
}

function Invoke-Step {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][scriptblock]$Script
    )
    Write-Log -Level INFO -Message ("--- {0} ---" -f $Title)
    try {
        & $Script
        Write-Log -Level OK -Message ("{0} completado." -f $Title)
    } catch {
        $msg = $_.Exception.Message
        Write-Log -Level ERR -Message ("{0} FALLÓ: {1}" -f $Title, $msg)
    }
}

Write-Log -Level INFO -Message "Inicio del proceso. Log: $LogFile"

# ========== 2) Cerrar procesos que bloquean ==========
Invoke-Step -Title "Cerrar Duet/iTunes si están abiertos" -Script {
    Get-Process duet*,itunes* -ErrorAction SilentlyContinue | Stop-Process -Force
}

# ========== 3) Desinstalar restos con winget (best-effort) ==========
Invoke-Step -Title "Desinstalar Apple iTunes (winget)" -Script {
    $found = winget list --exact --id Apple.iTunes 2>$null
    if ($LASTEXITCODE -eq 0 -and ($found -match "Apple\.iTunes")) {
        winget uninstall --exact --id Apple.iTunes --silent --accept-source-agreements --accept-package-agreements | Out-Null
    } else {
        Write-Log -Level WARN -Message "Apple iTunes no encontrado para desinstalar (continuamos)."
    }
}
Invoke-Step -Title "Desinstalar Apple Bonjour (winget)" -Script {
    $found = winget list --exact --id Apple.Bonjour 2>$null
    if ($LASTEXITCODE -eq 0 -and ($found -match "Apple\.Bonjour")) {
        winget uninstall --exact --id Apple.Bonjour --silent --accept-source-agreements --accept-package-agreements | Out-Null
    } else {
        Write-Log -Level WARN -Message "Apple Bonjour no encontrado para desinstalar (continuamos)."
    }
}

# ========== 4) Instalar iTunes (Store) y Bonjour ==========
Invoke-Step -Title "Instalar Apple iTunes (winget/msstore)" -Script {
    winget install --exact --id Apple.iTunes --source msstore --silent --accept-source-agreements --accept-package-agreements | Out-Null
}
Invoke-Step -Title "Instalar Apple Bonjour (winget)" -Script {
    winget install --exact --id Apple.Bonjour --silent --accept-source-agreements --accept-package-agreements | Out-Null
}

# ========== 5) Forzar instalación del driver USB Apple si existe ==========
Invoke-Step -Title "Instalar/forzar controlador Apple USB (pnputil)" -Script {
    $drvDir = "C:\Program Files\Common Files\Apple\Mobile Device Support\Drivers"
    $inf = Join-Path $drvDir "usbaapl64.inf"
    if (Test-Path $inf) {
        Write-Log -Level INFO -Message ("INF encontrado: {0}" -f $inf)
        pnputil /add-driver "`"$inf`"" /install | Out-Null
    } else {
        Write-Log -Level WARN -Message "No se encontró usbaapl64.inf. La versión de iTunes de la Store puede no instalar INF clásicos. Si USB sigue sin funcionar, instala iTunes 'clásico' desde Apple.com y reejecuta este script."
    }
}

# ========== 6) Reiniciar/asegurar AMDS ==========
Invoke-Step -Title "Configurar e iniciar Apple Mobile Device Service (AMDS)" -Script {
    $amds = Get-Service | Where-Object { $_.DisplayName -like "Apple Mobile Device*" -or $_.Name -like "AppleMobileDevice*" } | Select-Object -First 1
    if ($amds) {
        & sc.exe config $($amds.Name) start= auto | Out-Null
        if ($amds.Status -eq 'Running') {
            Restart-Service -Name $amds.Name -Force
        } else {
            Start-Service -Name $amds.Name
        }
        Start-Sleep -Seconds 2
        $st = (Get-Service -Name $amds.Name).Status
        Write-Log -Level INFO -Message ("Estado AMDS: {0}" -f $st)
    } else {
        throw "Servicio AMDS no encontrado."
    }
}

# ========== 7) (Opcional) Desactivar 'Apple Mobile Device Ethernet' ==========
Invoke-Step -Title "Desactivar adaptador 'Apple Mobile Device Ethernet' (opcional)" -Script {
    $eth = Get-NetAdapter | Where-Object {$_.Name -like "*Apple Mobile Device Ethernet*"}
    if ($eth) {
        $eth | Disable-NetAdapter -Confirm:$false
        Write-Log -Level INFO -Message "Adaptador desactivado para evitar modo NCM."
    } else {
        Write-Log -Level INFO -Message "Adaptador 'Apple Mobile Device Ethernet' no encontrado (no es problema)."
    }
}

# ========== 8) Relanzar Duet ==========
Invoke-Step -Title "Relanzar Duet" -Script {
    $duetCandidates = @(
        "$env:LOCALAPPDATA\Programs\Duet\Duet.exe",
        "$env:ProgramFiles\Duet\Duet.exe",
        "${env:ProgramFiles(x86)}\Duet\Duet.exe"
    )
    $duetExe = $duetCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($duetExe) {
        Start-Process -FilePath $duetExe | Out-Null
        Write-Log -Level INFO -Message ("Duet lanzado: {0}" -f $duetExe)
    } else {
        Write-Log -Level WARN -Message "Duet.exe no encontrado en rutas comunes. Ábrelo manualmente si es necesario."
    }
}

# ========== 9) Comprobaciones finales ==========
Invoke-Step -Title "Comprobación dispositivos PnP Apple" -Script {
    $devs = Get-PnpDevice | Where-Object { $_.FriendlyName -like "*Apple Mobile Device*" }
    if ($devs) {
        $table = $devs | Select-Object Status, Class, FriendlyName, InstanceId
        $table | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Log -Level INFO -Message $_.TrimEnd() }
        if ($devs.Status -contains "OK") {
            Write-Log -Level OK -Message "Al menos un dispositivo Apple Mobile Device está en estado OK."
        } else {
            Write-Log -Level WARN -Message "Aún aparecen como 'Unknown'. Si tras reconectar el iPad (desbloqueado y pulsando 'Confiar') sigue igual, instala iTunes clásico desde Apple.com."
        }
    } else {
        Write-Log -Level WARN -Message "No se detectaron dispositivos Apple Mobile Device (revisa cable/puerto y desbloqueo del iPad)."
    }
}

Write-Log -Level INFO -Message "Proceso finalizado."

# ========== 10) Abrir log automáticamente si hubo errores ==========
if ($global:HadErrors) {
    Write-Host "`nSe detectaron errores. Abriendo log..." -ForegroundColor Yellow
    Start-Process notepad.exe $LogFile
} else {
    Write-Host "`nSin errores críticos. Log en: $LogFile" -ForegroundColor Green
}