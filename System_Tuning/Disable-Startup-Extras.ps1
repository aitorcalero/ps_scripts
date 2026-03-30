[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [switch]$ForceDisableTailscale,      # Por defecto NO tocamos Tailscale (VPN)
  [switch]$ForceDisableSecurityHealth  # Por defecto NO tocamos el icono del Centro de Seguridad
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info($msg){ Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Warn($msg){ Write-Warning $msg }

# --- Requiere privilegios de admin para HKLM/servicios ---
function Require-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Este script debe ejecutarse como Administrador."
  }
}

Require-Admin

# --- Ubicaciones clave ---
$startupUser = Join-Path $env:AppData 'Microsoft\Windows\Start Menu\Programs\Startup'
$backupRoot  = Join-Path $env:ProgramData 'WorkstationOptimize\StartupBackup'
if (!(Test-Path $backupRoot)) { New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null }

# --- Utilidad: mover acceso directo si existe (reversible) ---
function Move-IfExists {
  param([Parameter(Mandatory)][string]$Pattern)
  try {
    $items = Get-ChildItem -Path $startupUser -Filter $Pattern -ErrorAction SilentlyContinue
    foreach($it in $items){
      $dest = Join-Path $backupRoot $it.Name
      if ($PSCmdlet.ShouldProcess($it.FullName, ("Mover a backup → {0}" -f $dest))) {
        Move-Item -Path $it.FullName -Destination $dest -Force
        Write-Info ("Movido a backup: {0}" -f $it.Name)
      }
    }
  } catch { Write-Warn "No se pudo mover '$Pattern': $($_.Exception.Message)" }
}

# --- Utilidad: comprobar existencia de valor en Run ---
function Test-RunValue {
  param([string]$HivePath,[string]$ValueName)
  try {
    $prop = Get-ItemProperty -Path $HivePath -ErrorAction SilentlyContinue
    return ($prop -and $prop.PSObject.Properties.Match($ValueName).Count -gt 0)
  } catch { return $false }
}

# --- Utilidad: eliminar valor Run si existe (corrige ':' usando formato) ---
function Remove-RunValue {
  param([Parameter(Mandatory)][string]$HivePath, [Parameter(Mandatory)][string]$ValueName)
  if (Test-RunValue -HivePath $HivePath -ValueName $ValueName) {
    $target = ("{0}:{1}" -f $HivePath, $ValueName)  # ← evita parser error
    if ($PSCmdlet.ShouldProcess($target,"Remove-ItemProperty")) {
      try {
        Remove-ItemProperty -Path $HivePath -Name $ValueName -ErrorAction SilentlyContinue
        Write-Info ("Eliminado Run: {0} → {1}" -f $HivePath, $ValueName)
      } catch { Write-Warn "No se pudo eliminar '{0}' en '{1}': {2}" -f $ValueName, $HivePath, $_.Exception.Message }
    }
  }
}

# --- Utilidad: deshabilitar servicio si existe ---
function Disable-ServiceIfPresent {
  param([Parameter(Mandatory)][string]$ServiceNameOrDisplay)
  try {
    $svc = Get-Service -ErrorAction SilentlyContinue | Where-Object {
      $_.Name -eq $ServiceNameOrDisplay -or $_.DisplayName -eq $ServiceNameOrDisplay
    }
    foreach($s in $svc){
      if ($PSCmdlet.ShouldProcess(("Service:{0}" -f $s.Name),"Set-Service Disabled")) {
        try {
          if ($s.Status -eq 'Running') { Stop-Service -Name $s.Name -Force -ErrorAction SilentlyContinue }
          Set-Service -Name $s.Name -StartupType Disabled
          Write-Info ("Servicio deshabilitado: {0} [{1}]" -f $s.DisplayName, $s.Name)
        } catch { Write-Warn "No se pudo deshabilitar servicio '{0}': {1}" -f $s.Name, $_.Exception.Message }
      }
    }
  } catch { Write-Warn "Error gestionando servicio '{0}': {1}" -f $ServiceNameOrDisplay, $_.Exception.Message }
}

# --- 1) Accesos directos en Startup (mover a backup, reversible) ---
# Abreviaturas, Enviar a OneNote, Ollama, ZoomIt, Greenshot, Discord, Docker, LM Studio, Ditto, iTunesHelper, Duet
'Abreviaturas.lnk',
'Enviar a OneNote*.lnk',
'Ollama*.lnk',
'ZoomIt*.lnk',
'Greenshot*.lnk',
'Discord*.lnk',
'Docker*.lnk',
'LM Studio*.lnk',
'Ditto*.lnk',
'iTunesHelper*.lnk',
'Duet*.lnk' | ForEach-Object { Move-IfExists -Pattern $_ }

# --- 2) Entradas HKCU/HKLM Run (eliminar si existen) ---
# HKCU
$HKCU_RUN = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
'Docker Desktop','Discord','Ditto','Greenshot','iTunesHelper','Duet' | ForEach-Object {
  Remove-RunValue -HivePath $HKCU_RUN -ValueName $_
}
# HKLM
$HKLM_RUN = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
'Duet','Greenshot','iTunesHelper' | ForEach-Object {
  Remove-RunValue -HivePath $HKLM_RUN -ValueName $_
}

# --- 3) Servicios/autoarranque específicos ---
# LM Studio
'LM Studio','LM Studio Service','electron.app.LM Studio' | ForEach-Object { Disable-ServiceIfPresent -ServiceNameOrDisplay $_ }
# Duet Display
'Duet','Duet Display' | ForEach-Object { Disable-ServiceIfPresent -ServiceNameOrDisplay $_ }
# Docker Desktop
'com.docker.service' | ForEach-Object { Disable-ServiceIfPresent -ServiceNameOrDisplay $_ }
# Ollama (si existe)
'Ollama' | ForEach-Object { Disable-ServiceIfPresent -ServiceNameOrDisplay $_ }

# --- 4) Entradas especiales/temporales ---
# BingWallpaperDaemon residual en Temp (seguro eliminar si existe)
$bingDaemonGlob = ('C:\Users\{0}\AppData\Local\Temp\bwp*' -f $env:USERNAME)
Get-ChildItem -Path $bingDaemonGlob -ErrorAction SilentlyContinue | ForEach-Object {
  $uninst = Join-Path $_.FullName 'UnInstDaemon.exe'
  if (Test-Path $uninst -PathType Leaf -ErrorAction SilentlyContinue) {
    if ($PSCmdlet.ShouldProcess($uninst,"Eliminar residual")) {
      try { Remove-Item $uninst -Force -ErrorAction Stop; Write-Info ("Eliminado residual: {0}" -f $uninst) } catch {}
    }
  }
}
# My Signins (posible acceso vacío)
Move-IfExists -Pattern 'My Signins*.lnk'

# --- 5) Elementos que NO tocamos por defecto (seguridad/VPN) ---
# Tailscale (VPN)
if ($ForceDisableTailscale) {
  Remove-RunValue -HivePath $HKCU_RUN -ValueName 'Tailscale'
  Disable-ServiceIfPresent -ServiceNameOrDisplay 'Tailscale'
} else {
  Write-Info "Tailscale (VPN) conservado. Usa -ForceDisableTailscale si deseas deshabilitarlo."
}
# SecurityHealthSystray (icono del Centro de Seguridad)
if ($ForceDisableSecurityHealth) {
  Remove-RunValue -HivePath $HKLM_RUN -ValueName 'SecurityHealth'
} else {
  Write-Info "SecurityHealth (Centro de Seguridad) conservado. Usa -ForceDisableSecurityHealth para deshabilitarlo."
}

Write-Info "Acciones completadas. Reinicia sesión para ver el impacto en el arranque."