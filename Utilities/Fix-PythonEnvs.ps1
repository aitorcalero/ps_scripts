#requires -Version 5.1
#requires -RunAsAdministrator
<#
.SYNOPSIS
  Auditoría, limpieza e instalación de entornos Python en Windows 11 (ES-es).

.DESCRIPTION
  - Detecta intérpretes de Python, rutas en PATH y herramientas de gestión.
  - Instala (opcional) Miniconda/pyenv-win/uv con winget.
  - Crea entorno de proyecto en modo Conda (ArcGIS) o uv (general).
  - Limpia PATH (opcional) de entradas obsoletas, con backup.
  - Genera log TXT y reporte JSON (idempotente, seguro).

.PARAMETER Profile
  auto | conda | uv  (por defecto: auto)

.PARAMETER InstallWingetTools
  Instala con winget las herramientas necesarias según perfil.

.PARAMETER ProjectName
  Nombre del proyecto/entorno (por defecto: python_sandbox).

.PARAMETER ProjectRoot
  Carpeta raíz del proyecto (por defecto: $env:USERPROFILE\Projects\python_sandbox).

.PARAMETER FixPath
  Limpia PATH (User/Machine) de rutas Python obsoletas con backup.

.PARAMETER IncludeArcgisApi
  En perfil conda: instalar 'arcgis' (pip) además de paquetes base.

.PARAMETER WhatIf
  Simula sin aplicar cambios (SupportsShouldProcess).

.NOTES
  Logs : %ProgramData%\PythonEnvFix\fix-python-envs.log
  JSON : %ProgramData%\PythonEnvFix\report-YYYYMMDD-HHMMSS.json
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [ValidateSet('auto','conda','uv')]
  [string]$Profile = 'auto',
  [switch]$InstallWingetTools,
  [string]$ProjectName = 'python_sandbox',
  [string]$ProjectRoot = "$env:USERPROFILE\Projects\python_sandbox",
  [switch]$FixPath,
  [switch]$IncludeArcgisApi,
  [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Logging/Estado ---
$Root     = "$env:ProgramData\PythonEnvFix"
$TxtLog   = Join-Path $Root "fix-python-envs.log"
$JsonPath = Join-Path $Root ("report-" + (Get-Date).ToString("yyyyMMdd-HHmmss") + ".json")
if (!(Test-Path $Root)) { New-Item -ItemType Directory -Path $Root -Force | Out-Null }
Start-Transcript -Path $TxtLog -Append -Force | Out-Null

$Result = [ordered]@{
  Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ssK")
  Preflight = [ordered]@{}
  Actions   = @()
  Warnings  = @()
  Errors    = @()
}

function Write-Info($msg){ if(-not $Quiet){ Write-Host "[INFO] $msg" -ForegroundColor Cyan } }
function Write-Warn($msg){ $Result.Warnings += $msg; if(-not $Quiet){ Write-Warning $msg } }
function Register-Action($title,$detail){ $Result.Actions += [ordered]@{ Step=$title; Detail=$detail } }

function Require-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = [Security.Principal.WindowsPrincipal]::new($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Este script debe ejecutarse como Administrador."
  }
}

function Invoke-WithRetry {
  param([scriptblock]$Action,[int]$MaxAttempts=3,[int]$InitialDelayMs=250,[string]$Operation="operación")
  $attempt=0; $delay=$InitialDelayMs
  while($attempt -lt $MaxAttempts){
    try{ & $Action; return } catch {
      $attempt++
      if($attempt -ge $MaxAttempts){ throw "Fallo en $Operation tras $MaxAttempts intentos: $($_.Exception.Message)" }
      Start-Sleep -Milliseconds $delay
      $delay=[math]::Min($delay*2,2000)
    }
  }
}

# --- Utilidades ---
function Winget-Available { return (Get-Command winget -ErrorAction SilentlyContinue) -ne $null }
function App-Installed {
  param([string]$ExeNameOrPath)
  return (Get-Command $ExeNameOrPath -ErrorAction SilentlyContinue) -ne $null
}
function Safe-StartWinget {
  param([Parameter(Mandatory)][string]$Id,[string]$ExtraArgs="--silent")
  if (Winget-Available) {
    $args = "install --id=$Id -e $ExtraArgs"
    if ($PSCmdlet.ShouldProcess("winget",$args)) {
      Start-Process -FilePath "winget" -ArgumentList $args -Wait -NoNewWindow
      Register-Action "winget install" "Id=$Id $ExtraArgs"
    }
  } else { Write-Warn "winget no disponible." }
}

function Detect-ArcGISConda {
  # ArcGIS Pro suele incluir conda en:
  $candidates = @(
    "C:\Program Files\ArcGIS\Pro\bin\Python\Scripts\conda.exe",
    "C:\Program Files\ArcGIS\Pro\bin\Python\Scripts\mamba.exe"
  )
  foreach($p in $candidates){ if(Test-Path $p){ return $true } }
  # O conda en PATH:
  return (Get-Command conda -ErrorAction SilentlyContinue) -ne $null
}

function Detect-Conda { return (Get-Command conda -ErrorAction SilentlyContinue) -ne $null }
function Detect-Pyenv { return ((Get-Command pyenv -ErrorAction SilentlyContinue) -ne $null -or (Test-Path "$env:USERPROFILE\.pyenv\pyenv-win\bin\pyenv.bat")) }
function Detect-UV    { return (Get-Command uv -ErrorAction SilentlyContinue) -ne $null }

function Ensure-Dir([string]$p){ if(!(Test-Path $p)){ New-Item -ItemType Directory -Path $p -Force | Out-Null } }

function Read-PATH {
  param([ValidateSet('User','Machine')][string]$Scope)
  return [System.Environment]::GetEnvironmentVariable('Path',$Scope)
}
function Write-PATH {
  param([ValidateSet('User','Machine')][string]$Scope,[string]$Value)
  [System.Environment]::SetEnvironmentVariable('Path',$Value,$Scope)
}

function Backup-PATH {
  $u = Read-PATH -Scope 'User'
  $m = Read-PATH -Scope 'Machine'
  $backup = [ordered]@{ User=$u; Machine=$m }
  $bkFile = Join-Path $Root ("PATH-backup-" + (Get-Date).ToString("yyyyMMdd-HHmmss") + ".json")
  $backup | ConvertTo-Json -Depth 4 | Out-File -FilePath $bkFile -Encoding UTF8 -Force
  Register-Action "Backup PATH" $bkFile
  return $backup
}

function Sanitize-PATH {
  param([ValidateSet('User','Machine')][string]$Scope,[string]$Original)
  # Quita rutas antiguas/conflictivas típicas de Python:
  $segments = $Original -split ';' | Where-Object { $_ -ne '' }
  $removePatterns = @(
    '\\Python\d+\.\d+\\Scripts\\?$',
    '\\Python\d+\.\d+\\?$',
    '\\Users\\[^\\]+\\AppData\\Local\\Programs\\Python\\Python\d+\\Scripts\\?$',
    '\\Users\\[^\\]+\\AppData\\Local\\Programs\\Python\\Python\d+\\?$'
  )
  $clean = @()
  foreach($s in $segments){
    $drop = $false
    foreach($rx in $removePatterns){ if($s -match $rx){ $drop=$true; break } }
    if(-not $drop){ $clean += $s }
  }
  return ($clean -join ';')
}

# --- Preflight ---
try {
  Require-Admin
  $Result.Preflight.Admin = $true
  $Result.Preflight.Winget = Winget-Available
  $Result.Preflight.Conda  = Detect-Conda
  $Result.Preflight.Pyenv  = Detect-Pyenv
  $Result.Preflight.UV     = Detect-UV
  # Mapear intérpretes
  $pyLaunchers = @()
  try { $pyLaunchers = & py -0p 2>$null } catch {}
  $Result.Preflight.PyLaunchers = $pyLaunchers
  # Heurística de ArcGIS
  $Result.Preflight.ArcGISConda = Detect-ArcGISConda
  # PATH actual
  $Result.Preflight.PathUser   = Read-PATH -Scope 'User'
  $Result.Preflight.PathMachine= Read-PATH -Scope 'Machine'
}
catch {
  $Result.Errors += $_.Exception.Message
  throw
}

# --- Selección de perfil ---
function Choose-Profile {
  param([string]$ProfileParam)
  if ($ProfileParam -eq 'conda'){ return 'conda' }
  if ($ProfileParam -eq 'uv'){     return 'uv' }
  # auto:
  if ($Result.Preflight.ArcGISConda -or $Result.Preflight.Conda){ return 'conda' }
  else { return 'uv' }
}
$chosen = Choose-Profile -ProfileParam $Profile
Register-Action "Perfil seleccionado" $chosen

# --- Instalación de herramientas (opcional) ---
if ($InstallWingetTools){
  if ($chosen -eq 'conda' -and -not (Detect-Conda)) {
    Safe-StartWinget -Id "Anaconda.Miniconda3" -ExtraArgs "--silent"
  }
  if ($chosen -eq 'uv' -and -not (Detect-Pyenv)) {
    Safe-StartWinget -Id "pyenv.pyenv-win" -ExtraArgs "--silent"
  }
  if ($chosen -eq 'uv' -and -not (Detect-UV)) {
    Safe-StartWinget -Id "astral-sh.uv" -ExtraArgs "--silent"
  }
}

# --- Crear proyecto/entorno ---
Ensure-Dir -p $ProjectRoot
$ProjectPath = Join-Path $ProjectRoot $ProjectName
Ensure-Dir -p $ProjectPath

switch ($chosen) {
  'conda' {
    if (-not (Detect-Conda)) {
      Write-Warn "Conda no está disponible tras instalación. Abre una nueva sesión o verifica App Installer."
    } else {
      $envName = $ProjectName
      if ($PSCmdlet.ShouldProcess("conda","create -n $envName python=3.11 -y")) {
        Invoke-WithRetry -Operation "conda create" -Action { conda create -n $envName python=3.11 -y | Out-Null }
        Register-Action "Conda env create" "name=$envName python=3.11"
      }
      if ($PSCmdlet.ShouldProcess("conda","install base pkgs")) {
        Invoke-WithRetry -Operation "conda install base" -Action { conda install -n $envName -y numpy pandas scipy jupyterlab | Out-Null }
        Register-Action "Conda install" "numpy,pandas,scipy,jupyterlab"
      }
      if ($IncludeArcgisApi) {
        if ($PSCmdlet.ShouldProcess("pip","install arcgis")) {
          Invoke-WithRetry -Operation "pip arcgis" -Action { conda run -n $envName python -m pip install --no-cache-dir arcgis | Out-Null }
          Register-Action "pip install" "arcgis (en $envName)"
        }
      }
      # Exportar environment.yml
      $yml = Join-Path $ProjectPath "environment.yml"
      if ($PSCmdlet.ShouldProcess("conda","env export > environment.yml")) {
        conda env export -n $envName --no-builds | Out-File -FilePath $yml -Encoding UTF8
        Register-Action "Export environment.yml" $yml
      }
    }
  }
  'uv' {
    if (-not (Detect-Pyenv)) { Write-Warn "pyenv-win no está disponible tras instalación; reabre terminal." }
    if (-not (Detect-UV))    { Write-Warn "uv no está disponible tras instalación; reabre terminal." }

    Push-Location $ProjectPath
    try {
      if ($PSCmdlet.ShouldProcess($ProjectPath,"uv init")) {
        if (-not (Test-Path (Join-Path $ProjectPath "pyproject.toml"))) { uv init | Out-Null }
        Register-Action "uv init" $ProjectPath
      }
      if ($PSCmdlet.ShouldProcess($ProjectPath,"uv add base pkgs")) {
        uv add numpy pandas requests | Out-Null
        Register-Action "uv add" "numpy,pandas,requests"
      }
      if ($PSCmdlet.ShouldProcess($ProjectPath,"uv venv")) {
        uv venv | Out-Null
        Register-Action "uv venv" ".venv creado"
      }
      if ($PSCmdlet.ShouldProcess($ProjectPath,"uv sync")) {
        uv sync | Out-Null
        Register-Action "uv sync" "instala según lock"
      }
    } finally { Pop-Location }
  }
}

# --- Limpieza del PATH (opcional y reversible) ---
if ($FixPath) {
  $bk = Backup-PATH
  $uOrig = $bk.User
  $mOrig = $bk.Machine
  $uNew  = Sanitize-PATH -Scope 'User'    -Original $uOrig
  $mNew  = Sanitize-PATH -Scope 'Machine' -Original $mOrig

  if ($PSCmdlet.ShouldProcess("PATH(User)","Sanitize")) {
    Write-PATH -Scope 'User' -Value $uNew
    Register-Action "PATH(User) sanitized" "Segmentos antiguos Python removidos"
  }
  if ($PSCmdlet.ShouldProcess("PATH(Machine)","Sanitize")) {
    Write-PATH -Scope 'Machine' -Value $mNew
    Register-Action "PATH(Machine) sanitized" "Segmentos antiguos Python removidos"
  }
}

# --- Informe y cierre ---
try {
  $Result | ConvertTo-Json -Depth 6 | Out-File -FilePath $JsonPath -Encoding UTF8 -Force
  Write-Info "Informe generado: $JsonPath"
} catch {
  $Result.Errors += "No se pudo escribir el JSON: $($_.Exception.Message)"
  Write-Warn $Result.Errors[-1]
}
Stop-Transcript | Out-Null
Write-Info "Finalizado. Reabre la terminal/VS Code para que PATH y herramientas queden activas."