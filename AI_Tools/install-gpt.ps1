<#
Instala el comando "gpt" en tu PowerShell profile (CurrentUserAllHosts).

Uso:
  1) Guarda como: install-gpt.ps1
  2) Ejecuta:     .\install-gpt.ps1
  3) Cierra y abre PowerShell
  4) Ejecuta:     gpt

Primera vez que ejecutes gpt:
- te pedirá la API key (entrada oculta)
- la guardará cifrada con DPAPI en %APPDATA%\GPT-CLI\openai_api_key.dpapi
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Install-GptProfile {
  [CmdletBinding()]
  param()

  $profilePath = $PROFILE.CurrentUserAllHosts

  $dir = Split-Path -Parent $profilePath
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  if (-not (Test-Path $profilePath)) { New-Item -ItemType File -Path $profilePath | Out-Null }

  $markerBegin = "# --- GPT CLI (OpenAI API) BEGIN ---"
  $markerEnd   = "# --- GPT CLI (OpenAI API) END ---"

  $existing = Get-Content -Raw -Path $profilePath
  if ($existing -match [regex]::Escape($markerBegin)) {
    Write-Host "Ya existe un bloque instalado en: $profilePath" -ForegroundColor Yellow
    Write-Host "Si falla, borra el bloque entre BEGIN/END y vuelve a ejecutar este instalador." -ForegroundColor Yellow
    return
  }

  # Bloque NO expandible: @' ... '@  (aquí NO se evalúan $variables)
  $blockCore = @'
Set-StrictMode -Version Latest

function Get-GptKeyPath {
  $baseDir = Join-Path $env:APPDATA "GPT-CLI"
  if (-not (Test-Path $baseDir)) { New-Item -ItemType Directory -Path $baseDir | Out-Null }
  Join-Path $baseDir "openai_api_key.dpapi"
}

function Ensure-Tls12 {
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  } catch { }
}

function Save-OpenAIKey {
  [CmdletBinding()]
  param([Parameter(Mandatory=$true)][securestring]$SecureKey)

  $path = Get-GptKeyPath
  # DPAPI por usuario (sin -Key)
  $cipher = $SecureKey | ConvertFrom-SecureString
  Set-Content -Path $path -Value $cipher -Encoding ASCII -Force
}

function Load-OpenAIKeyPlain {
  [CmdletBinding()]
  param()

  $path = Get-GptKeyPath
  if (-not (Test-Path $path)) { return $null }

  $cipher = Get-Content -Path $path -Raw
  if ([string]::IsNullOrWhiteSpace($cipher)) { return $null }

  $secure = $cipher | ConvertTo-SecureString

  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try {
    [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) | Out-Null
  }
}

function Ensure-OpenAIKey {
  [CmdletBinding()]
  param()

  if (-not [string]::IsNullOrWhiteSpace($env:OPENAI_API_KEY)) { return }

  $plain = Load-OpenAIKeyPlain
  if (-not [string]::IsNullOrWhiteSpace($plain)) {
    $env:OPENAI_API_KEY = $plain
    return
  }

  Write-Host "No hay API key guardada." -ForegroundColor Yellow
  Write-Host "Pégala ahora (entrada oculta). Se guardará cifrada para tu usuario de Windows." -ForegroundColor Yellow
  $sec = Read-Host -Prompt "OpenAI API key" -AsSecureString

  if ($sec.Length -lt 20) { throw "La clave parece demasiado corta. Cancelo." }

  Save-OpenAIKey -SecureKey $sec

  $plain2 = Load-OpenAIKeyPlain
  if ([string]::IsNullOrWhiteSpace($plain2)) { throw "No se pudo cargar la key tras guardarla (error inesperado)." }

  $env:OPENAI_API_KEY = $plain2
  Write-Host "OK. API key guardada y cargada." -ForegroundColor Green
}

function Reset-GptKey {
  [CmdletBinding()]
  param()

  $path = Get-GptKeyPath
  if (Test-Path $path) {
    Remove-Item -Path $path -Force
    Write-Host "Key borrada. La próxima vez que ejecutes gpt se pedirá de nuevo." -ForegroundColor Yellow
  } else {
    Write-Host "No había key guardada." -ForegroundColor Yellow
  }

  if (Test-Path Env:OPENAI_API_KEY) {
    Remove-Item Env:OPENAI_API_KEY -ErrorAction SilentlyContinue
  }
}

function Invoke-OpenAIChatCompletion {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)][array]$Messages,
    [string]$Model = "gpt-4o-mini",
    [double]$Temperature = 0.2,
    [int]$MaxTokens = 800
  )

  Ensure-Tls12
  Ensure-OpenAIKey

  $uri = "https://api.openai.com/v1/chat/completions"
  $headers = @{
    "Authorization" = "Bearer $env:OPENAI_API_KEY"
    "Content-Type"  = "application/json"
  }

  $body = @{
    model       = $Model
    messages    = $Messages
    temperature = $Temperature
    max_tokens  = $MaxTokens
  } | ConvertTo-Json -Depth 10

  try {
    $resp = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body -TimeoutSec 120
  } catch {
    $msg = $_.Exception.Message
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $msg += "`n" + $_.ErrorDetails.Message }
    throw "Error llamando a OpenAI API: $msg"
  }

  if (-not $resp.choices -or -not $resp.choices[0].message -or -not $resp.choices[0].message.content) {
    throw "Respuesta inesperada de la API (sin texto)."
  }

  [string]$resp.choices[0].message.content
}

function Start-Gpt {
  [CmdletBinding()]
  param([string]$Model = "gpt-4o-mini")

  $script:GptHistory = @(
    @{ role = "system"; content = "Responde en español, directo y práctico. Si falta info, pregunta lo mínimo." }
  )

  Write-Host "gpt listo. Comandos: /exit  /reset  /model <nombre>  /keyreset  /help" -ForegroundColor Cyan
  Write-Host ("Modelo actual: {0}" -f $Model) -ForegroundColor DarkCyan

  while ($true) {
    $user = Read-Host "tú"
    if ($null -eq $user) { continue }
    $user = $user.Trim()

    if ($user -eq "") { continue }
    if ($user -eq "/exit") { break }

    if ($user -eq "/help") {
      $helpText = "Comandos:`n" +
                  "  /exit                 salir`n" +
                  "  /reset                borrar historial de ESTA sesión`n" +
                  "  /model <nombre>       cambiar modelo (ej: /model gpt-4o-mini)`n" +
                  "  /keyreset             borrar la key guardada (se pedirá otra vez)`n"
      Write-Host $helpText -ForegroundColor DarkGray
      continue
    }

    if ($user -eq "/reset") {
      $script:GptHistory = @(
        @{ role = "system"; content = "Responde en español, directo y práctico. Si falta info, pregunta lo mínimo." }
      )
      Write-Host "Historial reseteado." -ForegroundColor Yellow
      continue
    }

    if ($user -eq "/keyreset") {
      Reset-GptKey
      continue
    }

    if ($user -like "/model *") {
      $newModel = $user.Substring(7).Trim()
      if ($newModel) {
        $Model = $newModel
        Write-Host ("Modelo cambiado a: {0}" -f $Model) -ForegroundColor Yellow
      } else {
        Write-Host "Uso: /model <nombre>" -ForegroundColor Yellow
      }
      continue
    }

    $script:GptHistory += @{ role = "user"; content = $user }

    try {
      $answer = Invoke-OpenAIChatCompletion -Messages $script:GptHistory -Model $Model
      Write-Host ""
      Write-Host ("asistente> {0}" -f $answer)
      Write-Host ""
      $script:GptHistory += @{ role = "assistant"; content = $answer }
    } catch {
      Write-Host ""
      Write-Host ("ERROR: {0}" -f $_.Exception.Message) -ForegroundColor Red
      Write-Host ""
    }
  }
}

Set-Alias -Name gpt -Value Start-Gpt
'@

  $fullBlock = @"
$markerBegin
$blockCore
$markerEnd
"@

  Add-Content -Path $profilePath -Value "`n$fullBlock`n"
  Write-Host "Instalado en: $profilePath" -ForegroundColor Green
  Write-Host "Cierra y abre PowerShell. Luego ejecuta: gpt" -ForegroundColor Green
}

try {
  Install-GptProfile
} catch {
  Write-Host ("ERROR: {0}" -f $_.Exception.Message) -ForegroundColor Red
  throw
}
