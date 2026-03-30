<#
.SYNOPSIS
  Audita tareas programadas y marca posibles candidatas a revisión/retirada.

.PARAMETER DaysStale
  Días a partir de los cuales una tarea se considera “antigua” si no se ejecuta (LastRunTime).

.PARAMETER FailThreshold
  Nº mínimo de ejecuciones fallidas para marcar como “FallosRepetidos”.

.PARAMETER IncludeMicrosoft
  Incluye también tareas bajo \Microsoft\ (por defecto solo tareas de usuario/terceros).

.PARAMETER ExportCsv
  Ruta opcional para exportar el informe en CSV.

.EXAMPLE
  .\Audit-ScheduledTasks.ps1

.EXAMPLE
  .\Audit-ScheduledTasks.ps1 -DaysStale 45 -FailThreshold 2 -ExportCsv C:\Temp\tareas.csv
#>
[CmdletBinding()]
param(
  [int]$DaysStale = 60,
  [int]$FailThreshold = 3,
  [switch]$IncludeMicrosoft,
  [string]$ExportCsv
)

function Get-UserFromPrincipal {
  param([string]$UserId)
  if ([string]::IsNullOrWhiteSpace($UserId)) { return $null }
  try {
    if ($UserId -match 'S-1-5-.*') {
      $sid = New-Object System.Security.Principal.SecurityIdentifier($UserId)
      return ($sid.Translate([System.Security.Principal.NTAccount])).Value
    }
    return $UserId
  } catch { return $UserId }
}

function Get-ActionTargetPath {
  param($Action)
  # Devuelve ruta ejecutable/objetivo y, si detecta PowerShell con -File, la ruta del script
  $exe = $Action.Execute
  $args = $Action.Arguments
  $result = [pscustomobject]@{
    ExecutePath     = $exe
    PowerShellFile  = $null
  }
  if ($exe -match '(?i)powershell\.exe|pwsh\.exe') {
    if ($args) {
      # Busca -File "C:\ruta\script.ps1" o -File C:\ruta\script.ps1
      if ($args -match '(?i)(?:^|\s)-File\s+"([^"]+)"') {
        $result.PowerShellFile = $Matches[1]
      } elseif ($args -match '(?i)(?:^|\s)-File\s+([^\s]+)') {
        $result.PowerShellFile = $Matches[1]
      }
    }
  }
  return $result
}

$now = Get-Date
$staleCutoff = $now.AddDays(-$DaysStale)

# 1) Recupera tareas
$all = Get-ScheduledTask 2>$null

if (-not $IncludeMicrosoft) {
  $all = $all | Where-Object { $_.TaskPath -notlike '\Microsoft*' }
}

# 2) Une con su info de ejecución
$report = foreach ($t in $all) {
  $info = $null
  try { $info = $t | Get-ScheduledTaskInfo } catch {}

  # Flags base
  $disabled         = ($t.State -eq 'Disabled')
  $noTriggers       = -not $t.Triggers -or $t.Triggers.Count -eq 0
  $noActions        = -not $t.Actions -or $t.Actions.Count -eq 0
  $lastRun          = $info?.LastRunTime
  $nextRun          = $info?.NextRunTime
  $lastResult       = $info?.LastTaskResult
  $neverRan         = (-not $lastRun) -or ($lastRun -as [DateTime] -eq [DateTime]::MinValue)
  $tooOld           = $lastRun -and ($lastRun -lt $staleCutoff)
  $noNextRun        = (-not $nextRun) -or ($nextRun -as [DateTime] -eq [DateTime]::MinValue)

  # Acciones y existencia de rutas
  $targetsMissing = $false
  $psScriptMissing = $false
  $actionsParsed = @()
  foreach ($a in ($t.Actions | ForEach-Object {[pscustomobject]$_})) {
    $parsed = Get-ActionTargetPath -Action $a
    $execOk = $true
    if ($parsed.ExecutePath -and -not (Test-Path $parsed.ExecutePath)) { $execOk = $false }
    if (-not $execOk) { $targetsMissing = $true }

    $psOk = $true
    if ($parsed.PowerShellFile) {
      # Expande variables de entorno en caso de que vengan sin expandir
      $psFile = [Environment]::ExpandEnvironmentVariables($parsed.PowerShellFile)
      if (-not (Test-Path $psFile)) { $psOk = $false; $psScriptMissing = $true }
    }

    $actionsParsed += [pscustomobject]@{
      ExecutePath    = $parsed.ExecutePath
      PowerShellFile = $parsed.PowerShellFile
      ExecuteExists  = $execOk
      PSFileExists   = $psOk
      Arguments      = $a.Arguments
    }
  }

  # Fallos repetidos: no hay contador oficial; usamos heurística:
  # si LastTaskResult != 0 y LastRunTime está dentro de los últimos X días, la marcamos.
  $repeatFail = ($lastResult -ne $null -and $lastResult -ne 0 -and ($lastRun -gt $staleCutoff))

  # Usuario asociado
  $principal = $t.Principal
  $userId = $principal.UserId
  $userResolved = Get-UserFromPrincipal -UserId $userId
  $userMissing  = $false
  if ($userResolved -and $userResolved -match '\\') {
    # Intenta comprobar que el usuario exista localmente o en dominio
    try {
      $null = New-Object System.Security.Principal.NTAccount($userResolved)
    } catch { $userMissing = $true }
  }

  # Motivos recomendación
  $reasons = @()
  if ($disabled)        { $reasons += 'Deshabilitada' }
  if ($noTriggers)      { $reasons += 'SinTriggers' }
  if ($noActions)       { $reasons += 'SinAcciones' }
  if ($targetsMissing)  { $reasons += 'EjecutableNoExiste' }
  if ($psScriptMissing) { $reasons += 'ScriptPSNoExiste' }
  if ($neverRan)        { $reasons += 'NuncaSeEjecuto' }
  if ($tooOld)          { $reasons += "UltimaEjecucion>=$DaysStale dias" }
  if ($noNextRun)       { $reasons += 'SinProximaEjecucion' }
  if ($repeatFail)      { $reasons += 'FalloReciente' }
  if ($userMissing)     { $reasons += 'UsuarioNoResuelto' }

  [pscustomobject]@{
    TaskPath          = $t.TaskPath
    TaskName          = $t.TaskName
    State             = $t.State
    User              = $userResolved
    RunLevel          = $principal.RunLevel
    LastRunTime       = $lastRun
    LastTaskResult    = $lastResult
    NextRunTime       = $nextRun
    Disabled          = $disabled
    SinTriggers       = $noTriggers
    SinAcciones       = $noActions
    EjecutableNoExiste= $targetsMissing
    ScriptPSNoExiste  = $psScriptMissing
    NuncaSeEjecuto    = $neverRan
    UltimaMuyAntigua  = $tooOld
    SinProximaEjec    = $noNextRun
    FalloReciente     = $repeatFail
    UsuarioNoResuelto = $userMissing
    Motivos           = ($reasons -join '; ')
    Acciones          = ($actionsParsed | ConvertTo-Json -Compress)
  }
}

# Ordenar por “más sospechosas” primero
$report = $report | Sort-Object {
  -not [string]::IsNullOrEmpty($_.Motivos)
}, @{
  Expression = { $_.LastRunTime }
  Ascending = $true
}

# Salida
$report | Format-Table -AutoSize TaskPath, TaskName, State, LastRunTime, NextRunTime, Motivos

if ($ExportCsv) {
  $report | Export-Csv -Path $ExportCsv -NoTypeInformation -Encoding UTF8
  Write-Host "Informe exportado a: $ExportCsv"
}
