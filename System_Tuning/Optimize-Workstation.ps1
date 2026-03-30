#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Optimización y auditoría seguras para HP ZBook G9 / Windows 11 (ES-es).
.DESCRIPTION
  - HealthCheck: SOLO audita y genera informe JSON (sin cambios).
  - EnableAll: aplica optimizaciones (energía, inicio, memoria/paginación, Storage Sense, servicios, SSD/TRIM).
  - InstallHealthCheckTask: crea opcionalmente una tarea semanal para ejecutar -HealthCheck -Quiet.
  - Idempotente, con manejo de errores y reintentos.
.NOTES
  Logs: %ProgramData%\WorkstationOptimize\optimize.log (TXT)
        %ProgramData%\WorkstationOptimize\healthcheck-*.json / optimize-result-*.json
  Seguridad: BitLocker/VBS/Credential Guard se AUDITAN (habilitar vía GPO/Intune).
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [switch]$EnableAll,
  [switch]$HealthCheck,
  [ValidateSet('Auto','Fixed')]
  [string]$PageFile = 'Auto',
  [int]$MinGB = 4,
  [int]$MaxGB = 16,
  [switch]$SkipCleanup,
  [switch]$KeepSearchIndexing,
  [switch]$InstallHealthCheckTask,
  [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Paths y estado ---
$LogRoot  = "$env:ProgramData\WorkstationOptimize"
$TxtLog   = Join-Path $LogRoot "optimize.log"
if (!(Test-Path $LogRoot)) { New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null }
Start-Transcript -Path $TxtLog -Append -Force | Out-Null

$Result = [ordered]@{
  Mode      = if ($HealthCheck) { "HealthCheck" } elseif ($EnableAll) { "EnableAll" } else { "Interactive" }
  Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ssK")
  Preflight = [ordered]@{}
  Audit     = [ordered]@{}
  Changes   = @()
  Warnings  = @()
}

function Write-Info($msg) { if (-not $Quiet) { Write-Host "[INFO] $msg" -ForegroundColor Cyan } }
function Write-Warn($msg) { $Result.Warnings += $msg; if (-not $Quiet) { Write-Warning $msg } }
function Register-Change($title, $before, $after) { $Result.Changes += [ordered]@{ Item=$title; Before=$before; After=$after } }

function Require-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "Este script debe ejecutarse como Administrador." }
}

function Invoke-WithRetry {
  param(
    [Parameter(Mandatory)] [scriptblock]$Action,
    [int]$MaxAttempts = 3,
    [int]$InitialDelayMs = 250,
    [string]$Operation = "operación"
  )
  $attempt = 0
  $delay   = $InitialDelayMs
  while ($attempt -lt $MaxAttempts) {
    try { & $Action; return } catch {
      $attempt++
      if ($attempt -ge $MaxAttempts) { throw "Fallo en $Operation tras $MaxAttempts intentos: $($_.Exception.Message)" }
      Start-Sleep -Milliseconds $delay
      $delay = [math]::Min($delay * 2, 2000)
    }
  }
}

# ---------- Utilidades robustas ----------
function Get-ActiveScheme {
  # 1) Robusto e independiente de idioma
  try {
    $out = powercfg /getactivescheme 2>$null
    if ($out) {
      # "Power Scheme GUID: a1841308-... (High performance)" / "Esquema de energía GUID: ... (Alto rendimiento)"
      $mGuid = [regex]::Match($out, '([0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})')
      if ($mGuid.Success) {
        $guid = $mGuid.Groups[1].Value
        $mName = [regex]::Match($out, '\((.+?)\)\s*$')
        $name = if ($mName.Success) { $mName.Groups[1].Value } else { 'Active' }
        return [ordered]@{ GUID=$guid; Name=$name }
      }
    }
  } catch {}

  # 2) Fallback: /l + línea con asterisco inicial
  try {
    $schemes = powercfg /l
    if ($schemes) {
      $activeLine = ($schemes | Select-String -Pattern '^\s*\*').ToString()
      if ($activeLine) {
        $mGuid = [regex]::Match($activeLine, '([0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})')
        $guid = if ($mGuid.Success) { $mGuid.Value } else { $null }
        $name = ($activeLine -replace '^\s*\*\s*','').Trim()
        return [ordered]@{ GUID=$guid; Name=$name }
      }
    }
  } catch {}
  return $null
}

function SafeGetRegDword {
  param([string]$Path, [string]$Name)
  try {
    $key = Get-Item -Path $Path -ErrorAction SilentlyContinue
    if (-not $key) { return $null }
    $prop = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue
    if ($prop -and $prop.PSObject.Properties.Match($Name).Count -gt 0) {
      $val = $prop.$Name
      if ($val -is [int]) { return $val }
      [int]$conv = 0
      if ([int]::TryParse("$val",[ref]$conv)) { return $conv }
    }
    return $null
  } catch { return $null }
}

# --- Preflight ---
function Preflight {
  Require-Admin
  $os   = Get-CimInstance Win32_OperatingSystem
  $cs   = Get-CimInstance Win32_ComputerSystem

  $Result.Preflight.OSVersion = $os.Version
  $Result.Preflight.OSBuild   = $os.BuildNumber
  $Result.Preflight.Mobile    = $cs.PCSystemType -in 2,3
  $Result.Preflight.Admin     = $true

  foreach ($cmd in @("powercfg","Optimize-Volume","Get-PhysicalDisk","Get-Volume","Get-ScheduledTask","Get-ScheduledTaskInfo")) {
    $exists = (Get-Command $cmd -ErrorAction SilentlyContinue) -ne $null
    $Result.Preflight."Cmd:$cmd" = $exists
    if (-not $exists -and $cmd -eq "Optimize-Volume") { Write-Warn "Optimize-Volume no disponible; TRIM en modo fallback." }
  }
}

# ---------- AUDITORÍAS (no hacen cambios) ----------
function Audit-EnergyProfile {
  $active = Get-ActiveScheme
  if ($active) { $Result.Audit.EnergyProfile = $active }
  else { $Result.Audit.EnergyProfile = [ordered]@{ GUID=$null; Name="Unknown" }; Write-Warn "No se pudo detectar el esquema de energía activo." }
}

function Audit-Startup {
  $startup = @()
  try { $startup = Get-CimInstance Win32_StartupCommand } catch { Write-Warn "Inicio no disponible: $($_.Exception.Message)" }
  $safeVendors = @("Microsoft","HP","Intel","NVIDIA","Realtek","Synaptics","ESRI","HID","Bluetooth","Windows Security")
  $suspicious = @()
  foreach ($item in $startup) {
    $vendorHit = $safeVendors | Where-Object { $item.Command -match $_ }
    if (-not $vendorHit) { $suspicious += [ordered]@{Name=$item.Name; Command=$item.Command} }
  }
  $Result.Audit.Startup = [ordered]@{ SuspiciousCount=$suspicious.Count; Suspicious=$suspicious }

  $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
  $global = SafeGetRegDword -Path $regPath -Name "GlobalUserDisabled"
  $Result.Audit.BackgroundApps = if ($null -eq $global) { "NotConfigured" } elseif ($global -eq 1) { "Restricted" } else { "Allowed" }
}

function Audit-MemoryPaging {
  $memComp = $false
  try { $memComp = (Get-MMAgent).MemoryCompression } catch {}
  $cs      = Get-CimInstance Win32_ComputerSystem
  $pageSet = Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$($env:SystemDrive)\\pagefile.sys" }
  $pfMode  = if ($cs.AutomaticManagedPagefile) { "Automatic" } elseif ($pageSet) { "Fixed" } else { "Unknown" }
  $Result.Audit.Memory   = [ordered]@{ MemoryCompression=$memComp }
  $Result.Audit.PageFile = [ordered]@{
    Mode=$pfMode
    InitialMB= if ($pageSet) { $pageSet.InitialSize } else { $null }
    MaximumMB= if ($pageSet) { $pageSet.MaximumSize } else { $null }
  }
}

function Audit-StorageSense {
  $base = "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy"
  $keys = @("01","04","08","32","256")
  $vals = @{}
  foreach ($k in $keys) { $vals[$k] = SafeGetRegDword -Path $base -Name $k }
  $Result.Audit.StorageSense = $vals
}

function Audit-Services {
  $recommend = @(
    @{Name='DiagTrack';        Start='Manual'},
    @{Name='dmwappushservice'; Start='Manual'},
    @{Name='Fax';              Start='Disabled'},
    @{Name='XblGameSave';      Start='Disabled'},
    @{Name='XblAuthManager';   Start='Disabled'},
    @{Name='XboxGipSvc';       Start='Disabled'},
    @{Name='SharedAccess';     Start='Manual'}
  )
  if (-not $KeepSearchIndexing) { $recommend += @{Name='WSearch'; Start='Manual'} }
  $report = @()
  foreach ($r in $recommend) {
    $svc = Get-Service -Name $r.Name -ErrorAction SilentlyContinue
    if ($svc) { $report += [ordered]@{ Name=$r.Name; Current=$svc.StartType; Recommended=$r.Start; Aligned=($svc.StartType -eq $r.Start) } }
    else     { $report += [ordered]@{ Name=$r.Name; Current="Missing"; Recommended=$r.Start; Aligned=$true } }
  }
  $Result.Audit.Services = $report
}

function Audit-Drives {
  $hasOptimize = (Get-Command Optimize-Volume -ErrorAction SilentlyContinue) -ne $null
  $taskState = "NotFound"; $lastRun = $null
  try {
    $task = Get-ScheduledTask -TaskPath "\Microsoft\Windows\Defrag\" -TaskName "ScheduledDefrag" -ErrorAction SilentlyContinue
    if ($task) {
      $taskState = $task.State
      $info = Get-ScheduledTaskInfo -TaskName "ScheduledDefrag" -TaskPath "\Microsoft\Windows\Defrag\" -ErrorAction SilentlyContinue
      if ($info) { $lastRun = $info.LastRunTime }
    }
  } catch {}

  $vols = @(); try { $vols = Get-Volume | Where-Object { $_.DriveLetter } } catch {}

  $Result.Audit.Drives = [ordered]@{
    OptimizeVolumeAvailable = $hasOptimize
    ScheduledDefrag         = $taskState
    ScheduledDefragLastRun  = $lastRun
    Volumes = $vols | ForEach-Object {
      [ordered]@{
        DriveLetter = $_.DriveLetter
        FileSystem  = $_.FileSystemType
        HealthStatus= $_.HealthStatus
        SizeGB      = [math]::Round($_.Size/1GB, 2)
        FreeGB      = [math]::Round($_.SizeRemaining/1GB, 2)
      }
    }
  }
}

function Audit-Security {
  $bl = "Unknown"; try { $bl = (Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop).ProtectionStatus } catch {}
  $vbs = $null; $cg = $null
  try { $vbs = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -Name EnableVirtualizationBasedSecurity -ErrorAction Stop).EnableVirtualizationBasedSecurity } catch {}
  try { $cg  = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name LsaCfgFlags -ErrorAction SilentlyContinue).LsaCfgFlags } catch {}
  $Result.Audit.Security = [ordered]@{ BitLocker=$bl; VBS=$vbs; CredentialGuard=$cg }
}

# ---------- OPTIMIZACIONES ----------
function Set-EnergyProfile {
  Write-Info "Configurando plan de energía…"

  # 1) Intento directo: GUID estándar de "Alto rendimiento"
  $highGuid = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
  $active   = Get-ActiveScheme
  $currentGuid = if ($active) { $active.GUID } else { $null }

  if ($highGuid -and ($highGuid -ne $currentGuid)) {
    if ($PSCmdlet.ShouldProcess("Plan de energía", "Activar 'Alto rendimiento'")) {
      try {
        Invoke-WithRetry -Operation "powercfg /s HighPerf" -Action { powercfg /s $highGuid | Out-Null }
        Register-Change "Plan de energía" "GUID=$currentGuid" "GUID=$highGuid (Alto rendimiento)"
      } catch {
        Write-Warn "No se pudo aplicar directamente 'Alto rendimiento' por GUID: $($_.Exception.Message)"
      }
    }
  } else {
    Write-Info "Plan de energía ya es 'Alto rendimiento' o GUID desconocido."
  }

  # 2) Fallback: búsqueda en /l si el cambio anterior no se aplicó
  $activeAfter = Get-ActiveScheme
  if (-not $activeAfter -or $activeAfter.GUID -ne $highGuid) {
    try {
      $schemes = powercfg /l
      if ($schemes) {
        $highLine = ($schemes | Select-String -Pattern "High performance|Alto rendimiento").ToString()
        if ($highLine) {
          $mGuid = [regex]::Match($highLine, '([0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})')
          if ($mGuid.Success) {
            $guid = $mGuid.Value
            if ($guid -and ($guid -ne $currentGuid)) {
              if ($PSCmdlet.ShouldProcess("Plan de energía", "Activar 'Alto rendimiento' (fallback)")) {
                Invoke-WithRetry -Operation "powercfg /s fallback HighPerf" -Action { powercfg /s $guid | Out-Null }
                Register-Change "Plan de energía (fallback)" "GUID=$currentGuid" "GUID=$guid (Alto rendimiento)"
              }
            }
          }
        }
      }
    } catch {
      Write-Warn "Fallback de plan de energía con /l no disponible: $($_.Exception.Message)"
    }
  }

  # Ajustes comunes en AC
  if ($PSCmdlet.ShouldProcess("Power settings", "Ajustar monitor/standby/disk en AC")) {
    Invoke-WithRetry -Operation "powercfg /x" -Action {
      powercfg /x -monitor-timeout-ac 30
      powercfg /x -standby-timeout-ac 0
      powercfg /x -disk-timeout-ac 0
    }
  }
}

function Optimize-Startup {
  Write-Info "Auditoría de elementos de inicio…"
  try {
    $startup = Get-CimInstance Win32_StartupCommand
    $safeVendors = @("Microsoft","HP","Intel","NVIDIA","Realtek","Synaptics","ESRI","HID","Bluetooth","Windows Security")
    foreach ($item in $startup) {
      $vendorHit = $safeVendors | Where-Object { $item.Command -match $_ }
      if (-not $vendorHit) { Write-Warn "Elemento de inicio a revisar: $($item.Name) → $($item.Command)" }
    }
  } catch { Write-Warn "No se pudo enumerar el inicio: $($_.Exception.Message)" }

  # Apps en 2º plano: crea la clave si falta y escribe el valor sin fallar si no existe
  $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
  if (!(Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
  $current = SafeGetRegDword -Path $regPath -Name "GlobalUserDisabled"
  $target  = 1
  if ($current -ne $target) {
    if ($PSCmdlet.ShouldProcess("Background apps","Restringir ejecución en segundo plano")) {
      Invoke-WithRetry -Operation "Set GlobalUserDisabled=1" -Action {
        New-ItemProperty -Path $regPath -Name "GlobalUserDisabled" -Value $target -PropertyType DWord -Force | Out-Null
      }
      Register-Change "Apps en segundo plano (HKCU)" $current $target
    }
  }
}

function Tune-Memory {
  Write-Info "Ajustando políticas de memoria…"
  try {
    $memComp = (Get-MMAgent).MemoryCompression
    if (-not $memComp) {
      if ($PSCmdlet.ShouldProcess("MemoryCompression","Habilitar")) {
        Enable-MMAgent -MemoryCompression | Out-Null
        Register-Change "Compresión de memoria" "Disabled" "Enabled"
      }
    }
  } catch { Write-Warn "MMAgent no disponible: $($_.Exception.Message)" }

  $cs = Get-CimInstance Win32_ComputerSystem
  $pageSet = Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$($env:SystemDrive)\\pagefile.sys" }

  if ($PageFile -eq 'Auto') {
    if (-not $cs.AutomaticManagedPagefile) {
      if ($PSCmdlet.ShouldProcess("PageFile","Establecer en automático")) {
        Invoke-WithRetry -Operation "CIM: AutomaticManagedPagefile=True" -Action {
          Set-CimInstance -Query "SELECT * FROM Win32_ComputerSystem" -Property @{AutomaticManagedPagefile=$true} | Out-Null
        }
        Register-Change "PageFile (modo)" "Manual" "Automático"
      }
    }
  } else {
    $minMB = $MinGB * 1024
    $maxMB = $MaxGB * 1024
    $needsChange = $false
    if ($cs.AutomaticManagedPagefile) { $needsChange = $true }
    elseif ($pageSet) { if ($pageSet.InitialSize -ne $minMB -or $pageSet.MaximumSize -ne $maxMB) { $needsChange = $true } }
    else { $needsChange = $true }

    if ($needsChange) {
      if ($PSCmdlet.ShouldProcess("PageFile","Establecer tamaño fijo $MinGB–$MaxGB GB")) {
        Invoke-WithRetry -Operation "CIM: PageFile Fixed" -Action {
          Set-CimInstance -Query "SELECT * FROM Win32_ComputerSystem" -Property @{AutomaticManagedPagefile=$false} | Out-Null
          $existing = Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$($env:SystemDrive)\\pagefile.sys" }
          if ($existing) { Remove-CimInstance -InputObject $existing -ErrorAction SilentlyContinue }
          New-CimInstance -ClassName Win32_PageFileSetting -Property @{ Name="$($env:SystemDrive)\\pagefile.sys"; InitialSize=$minMB; MaximumSize=$maxMB } | Out-Null
        }
        Register-Change "PageFile (tamaño)" "Auto/otro" "$MinGB–$MaxGB GB"
      }
    }
  }
}

function Enable-StorageSense {
  Write-Info "Habilitando Storage Sense…"
  $base = "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy"
  if (!(Test-Path $base)) { New-Item -Path $base -Force | Out-Null }
  # Valores equilibrados (ES-es): ejecutar cada 30 días; papelera/descargas >14 días; temporales ON
  $desired = @{ "01"=1; "04"=1; "08"=30; "32"=14; "256"=14 }
  foreach ($k in $desired.Keys) {
    $current = SafeGetRegDword -Path $base -Name $k
    if ($current -ne $desired[$k]) {
      if ($PSCmdlet.ShouldProcess("StorageSense","Set $k=$($desired[$k])")) {
        Invoke-WithRetry -Operation "StorageSense-$k" -Action {
          New-ItemProperty -Path $base -Name $k -Value $desired[$k] -PropertyType DWord -Force | Out-Null
        }
        Register-Change "StorageSense:$k" $current $desired[$k]
      }
    }
  }
}

function Cleanup-Temp {
  if ($SkipCleanup) { Write-Info "Saltando limpieza por parámetro."; return }
  Write-Info "Limpiando temporales…"
  foreach ($p in @($env:TEMP,$env:TMP,"C:\Windows\Temp")) {
    if ($PSCmdlet.ShouldProcess($p,"Eliminar temporales")) {
      try {
        if (Test-Path $p) {
          # Intento no intrusivo: eliminar ficheros primero, luego directorios vacíos. Omitir bloqueados sin warning.
          Get-ChildItem $p -Force -Recurse -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer } | ForEach-Object {
            try { Remove-Item $_.FullName -Force -ErrorAction Stop } catch { }
          }
          Get-ChildItem $p -Force -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer } | Sort-Object FullName -Descending | ForEach-Object {
            try { Remove-Item $_.FullName -Force -Recurse -ErrorAction Stop } catch { }
          }
          Register-Change "Limpieza temporales" $p "Ejecutada (archivos en uso omitidos)"
        }
      } catch {
        Write-Warn "No se pudo limpiar '$p': $($_.Exception.Message)"
      }
    }
  }

  $wu = "C:\Windows\SoftwareDistribution\Download"
  if ((Test-Path $wu) -and $PSCmdlet.ShouldProcess($wu,"Vaciar caché Windows Update")) {
    try {
      Get-ChildItem $wu -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try { Remove-Item $_.FullName -Force -Recurse -ErrorAction Stop } catch { }
      }
      Register-Change "Caché Windows Update" $wu "Vacío (archivos en uso omitidos)"
    } catch {
      Write-Warn "No se pudo limpiar caché WU: $($_.Exception.Message)"
    }
  }
}

function Optimize-Services {
  Write-Info "Ajustando servicios no críticos…"
  $candidates = @(
    @{Name='DiagTrack';        Start='Manual'},
    @{Name='dmwappushservice'; Start='Manual'},
    @{Name='Fax';              Start='Disabled'},
    @{Name='XblGameSave';      Start='Disabled'},
    @{Name='XblAuthManager';   Start='Disabled'},
    @{Name='XboxGipSvc';       Start='Disabled'},
    @{Name='SharedAccess';     Start='Manual'}
  )
  if (-not $KeepSearchIndexing) { $candidates += @{Name='WSearch'; Start='Manual'} } else { Write-Info "Conservando Windows Search por parámetro." }

  foreach ($s in $candidates) {
    $svc = Get-Service -Name $s.Name -ErrorAction SilentlyContinue
    if ($svc -and $svc.StartType -ne $s.Start) {
      if ($PSCmdlet.ShouldProcess("Service: "+$s.Name, "Set StartupType "+$s.Start)) {
        try { Set-Service -Name $s.Name -StartupType $s.Start; Register-Change "Servicio $($s.Name)" $svc.StartType $s.Start }
        catch { Write-Warn "No se pudo cambiar '$($s.Name)': $($_.Exception.Message)" }
      }
    }
  }
}

function Optimize-Drives {
  Write-Info "Optimizando unidades (TRIM)…"
  $hasOptimize = (Get-Command Optimize-Volume -ErrorAction SilentlyContinue) -ne $null
  if ($hasOptimize) {
    if ($PSCmdlet.ShouldProcess("Unidades","Optimize-Volume /ReTrim")) {
      try {
        Get-Volume | Where-Object { $_.DriveLetter } | ForEach-Object {
          Optimize-Volume -DriveLetter $_.DriveLetter -ReTrim -ErrorAction Stop | Out-Null
          Register-Change "TRIM unidad $($_.DriveLetter)" "N/A" "Ejecutado"
        }
      } catch { Write-Warn "Optimize-Volume falló: $($_.Exception.Message)" }
    }
    try { Enable-ScheduledTask -TaskPath "\Microsoft\Windows\Defrag\" -TaskName "ScheduledDefrag" -ErrorAction SilentlyContinue | Out-Null } catch { Write-Warn "No se pudo habilitar ScheduledDefrag: $($_.Exception.Message)" }
  } else {
    Write-Warn "Optimize-Volume no disponible; intento TRIM en C: si procede."
    try { Optimize-Volume -DriveLetter C -ReTrim -ErrorAction Stop | Out-Null; Register-Change "TRIM unidad C" "N/A" "Ejecutado (fallback)" }
    catch { Write-Warn "Fallback TRIM C: no aplicable: $($_.Exception.Message)" }
  }
}

function Optimize-NetworkAdapters { Write-Info "Adaptadores de red: validar ahorro de energía en AC en el Administrador de dispositivos." }

# --- Seguridad (solo check; habilitar por GPO/Intune) ---
function Security-Checks {
  Write-Info "Comprobaciones de BitLocker/VBS/CG…"
  try { $Result.Preflight.BitLocker = (Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop).ProtectionStatus } catch { Write-Warn "Consulta BitLocker: $($_.Exception.Message)" }
  try {
    $Result.Preflight.VBS = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -Name EnableVirtualizationBasedSecurity -ErrorAction Stop).EnableVirtualizationBasedSecurity
    $Result.Preflight.CredentialGuard = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name LsaCfgFlags -ErrorAction SilentlyContinue).LsaCfgFlags
  } catch { Write-Warn "Lectura Device Guard/Credential Guard: $($_.Exception.Message)" }
  Write-Info "Para habilitar BitLocker/CG, usar GPO/Intune."
}

function Safe-UpdateHints { Write-Info "Drivers OEM: HP Support Assistant / Image Assistant; parches: Windows Update." }

# --- Tarea programada opcional para HealthCheck ---
function Ensure-HealthCheckTask {
  if (-not $InstallHealthCheckTask) { return }
  try {
    $taskName = "WorkstationHealthCheck"
    $exists = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($exists) { Write-Info "Tarea '$taskName' ya existe."; return }
    $action  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`" -HealthCheck -Quiet"
    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 08:30
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERNAME" -LogonType Interactive -RunLevel Highest
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Description "Auditoría semanal de salud de la estación de trabajo" | Out-Null
    Write-Info "Tarea programada '$taskName' instalada (lunes 08:30)."
  } catch { Write-Warn "No se pudo instalar la tarea programada: $($_.Exception.Message)" }
}

# ---------- EJECUCIÓN ----------
try {
  Preflight

  if ($HealthCheck) {
    Write-Info "Ejecutando auditoría (HealthCheck)…"
    Audit-EnergyProfile
    Audit-Startup
    Audit-MemoryPaging
    Audit-StorageSense
    Audit-Services
    Audit-Drives
    Audit-Security
    Ensure-HealthCheckTask

    $hcPath = Join-Path $LogRoot ("healthcheck-" + (Get-Date).ToString("yyyyMMdd-HHmmss") + ".json")
    $Result | ConvertTo-Json -Depth 6 | Out-File -FilePath $hcPath -Encoding UTF8 -Force
    Write-Info "Informe generado: $hcPath"
  }
  elseif ($EnableAll) {
    Set-EnergyProfile
    Optimize-Startup
    Tune-Memory
    Enable-StorageSense
    Optimize-Services
    Optimize-Drives
    Optimize-NetworkAdapters
    if (-not $SkipCleanup) { Cleanup-Temp }
    Security-Checks
    Safe-UpdateHints
    Ensure-HealthCheckTask

    $optPath = Join-Path $LogRoot ("optimize-result-" + (Get-Date).ToString("yyyyMMdd-HHmmss") + ".json")
    $Result | ConvertTo-Json -Depth 6 | Out-File -FilePath $optPath -Encoding UTF8 -Force
    Write-Info "Resumen de cambios: $optPath"
  }
  else {
    Write-Info "Modo interactivo. Usa -EnableAll (optimizar), -HealthCheck (auditar), -InstallHealthCheckTask (tarea semanal)."
  }

} catch {
  Write-Warn "Error no controlado: $($_.Exception.Message)"
  throw
} finally {
  Stop-Transcript | Out-Null
}