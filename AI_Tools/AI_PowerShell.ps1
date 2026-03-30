# ====================================================================================
# LLM-PS Terminal Booster (Ollama + PowerShell) — versión API pull
# Tested on: Windows 11, PowerShell 7+, NVIDIA GPU. Funciona en CPU si no hay GPU.
# ====================================================================================

if ($Global:LLM_PS_Initialized) { return }
$Global:LLM_PS_Initialized = $true

# Forzar UTF-8 para evitar caracteres "raros" en consola
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new() } catch {}

# --- Config por defecto (ajústala si quieres) --------------------------------------
$Global:LLM_PS_Config = [ordered]@{
  DefaultModel    = 'qwen2.5-coder:7b'      # Muy bueno para código. Alternativas: 'llama3.1:8b-instruct', 'mistral:7b-instruct'
  FallbackModel   = 'llama3.1:8b-instruct'  # Respaldo generalista
  ModelsToPull    = @('qwen2.5-coder:7b','llama3.1:8b-instruct')
  OllamaHost      = 'http://127.0.0.1:11434'
  CopyToClipboard = $true
  DefaultRun      = $false                  # Por defecto NO ejecuta (solo muestra). Usa -Run o el alias ai! para ejecutar.
  SafeMode        = $true                   # Chequeos básicos de seguridad antes de ejecutar
  SystemPrompt    = @"
Eres un generador de scripts de PowerShell. Devuelve EXCLUSIVAMENTE código PowerShell
en un único bloque de triple comilla (```powershell ... ```), sin texto adicional.
- Usa cmdlets nativos y prácticas seguras.
- Añade comentarios .SYNOPSIS y ejemplos mínimos cuando aplique.
- Si necesitas instalar módulos, muestra el código idempotente (comprobando existencia).
- Evita funciones destructivas salvo petición explícita del usuario; pide confirmación en el propio script con -Confirm.
"@
}

# --- Helpers ------------------------------------------------------------------------
function Test-Admin {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Ensure-WinGet {
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "⚠  winget no encontrado. Instálalo desde Microsoft Store (App Installer) y reintenta." -ForegroundColor Yellow
    throw "Falta winget"
  }
}

function Install-OllamaIfNeeded {
  if (Get-Command ollama -ErrorAction SilentlyContinue) { return }
  Ensure-WinGet
  Write-Host "⬇️  Instalando Ollama..." -ForegroundColor Cyan
  winget install -e --id Ollama.Ollama --accept-package-agreements --accept-source-agreements | Out-Null
  if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) { throw "No se pudo instalar Ollama." }
}

function Start-OllamaService {
  # En Windows, ollama instala un servicio (ollama) o usa `ollama serve`
  $svc = Get-Service -Name 'ollama' -ErrorAction SilentlyContinue
  if ($svc) {
    if ($svc.Status -ne 'Running') {
      Write-Host "▶️  Arrancando servicio Ollama..." -ForegroundColor Cyan
      Start-Service ollama
      $svc.WaitForStatus('Running','00:00:10') | Out-Null
    }
  } else {
    Write-Host "▶️  Lanzando 'ollama serve' en background..." -ForegroundColor Cyan
    Start-Process -WindowStyle Hidden -FilePath (Get-Command ollama).Source -ArgumentList 'serve'
    Start-Sleep -Seconds 2
  }
}

function Wait-Ollama {
  param([int]$TimeoutSec = 20)
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
    try {
      $r = Invoke-RestMethod -Method Get -Uri ($Global:LLM_PS_Config.OllamaHost + '/api/tags') -TimeoutSec 3
      if ($r) { return }
    } catch { Start-Sleep -Milliseconds 500 }
  }
  throw "Ollama API no responde en $TimeoutSec s."
}

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
# NUEVA versión: descarga modelos usando la API (sin spinner/ANSI/TTY)
function Install-OllamaModels {
  param([string[]]$Models = $Global:LLM_PS_Config.ModelsToPull)

  $base = $Global:LLM_PS_Config.OllamaHost.TrimEnd('/')
  foreach ($m in $Models) {
    Write-Host "⬇️  Descargando modelo (API): $m" -ForegroundColor Cyan
    $body = @{ name = $m; stream = $false } | ConvertTo-Json
    try {
      # /api/pull devuelve JSON con estado; stream=false evita progreso incremental.
      $resp = Invoke-RestMethod -Method Post -Uri "$base/api/pull" `
              -Body $body -ContentType 'application/json' -TimeoutSec 7200
      # Validamos que esté disponible después del pull
      $tags = Invoke-RestMethod -Method Get -Uri "$base/api/tags" -TimeoutSec 10
      if ($tags.models.name -notcontains $m) {
        throw "El modelo '$m' no aparece en /api/tags tras el pull."
      }
      Write-Host "✅ Modelo listo: $m" -ForegroundColor Green
    } catch {
      Write-Warning "No se pudo descargar '$m' por API: $($_.Exception.Message)"
      # Fallback opcional: intento con CLI pero silenciando cualquier spinner/ANSI
      try {
        & (Get-Command ollama).Source pull $m *> $null
        Write-Host "✅ Modelo listo (CLI fallback): $m" -ForegroundColor Green
      } catch {
        throw
      }
    }
  }
}
# <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

function Get-LLMModelsLocal {
  try {
    $tags = Invoke-RestMethod -Method Get -Uri ($Global:LLM_PS_Config.OllamaHost + '/api/tags') -TimeoutSec 5
    return @($tags.models.name)
  } catch {
    return @()
  }
}

function Select-AvailableModel {
  $local = Get-LLMModelsLocal
  if ($local -contains $Global:LLM_PS_Config.DefaultModel) { return $Global:LLM_PS_Config.DefaultModel }
  elseif ($local -contains $Global:LLM_PS_Config.FallbackModel) { return $Global:LLM_PS_Config.FallbackModel }
  elseif ($local.Count -gt 0) { return $local[0] }
  else { return $Global:LLM_PS_Config.DefaultModel }
}

function Invoke-OllamaGenerate {
  param(
    [Parameter(Mandatory)][string]$Model,
    [Parameter(Mandatory)][string]$Prompt,
    [string]$System = $Global:LLM_PS_Config.SystemPrompt,
    [switch]$Stream
  )
  $body = @{
    model  = $Model
    prompt = $Prompt
    system = $System
    stream = [bool]$Stream
    options = @{ temperature = 0.2 }
  } | ConvertTo-Json -Depth 6

  $uri = $Global:LLM_PS_Config.OllamaHost + '/api/generate'

  if ($Stream) {
    # Streaming manual (línea a línea)
    $handler = New-Object System.Net.Http.HttpClientHandler
    $client  = New-Object System.Net.Http.HttpClient($handler)
    $content = New-Object System.Net.Http.StringContent($body, [System.Text.Encoding]::UTF8, "application/json")
    $resp = $client.PostAsync($uri, $content, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
    $stream = $resp.Content.ReadAsStreamAsync().Result
    $sr = New-Object System.IO.StreamReader($stream)
    $sb = [System.Text.StringBuilder]::new()
    while(-not $sr.EndOfStream){
      $line = $sr.ReadLine()
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      try {
        $obj = $line | ConvertFrom-Json
        if ($obj.response) { [void]$sb.Append($obj.response) ; Write-Host -NoNewline $obj.response }
      } catch {
        # Ignorar basura parcial
      }
    }
    Write-Host
    return $sb.ToString()
  } else {
    $result = Invoke-RestMethod -Method Post -Uri $uri -Body $body -ContentType 'application/json' -TimeoutSec 600
    return $result.response
  }
}

function Extract-PowerShellCode {
  param([Parameter(Mandatory)][string]$Text)
  # Busca ```powershell ... ``` o ``` ... ```
  $regexes = @(
    '(?s)```powershell\s+(.*?)```',
    '(?s)```ps1\s+(.*?)```',
    '(?s)```\s*(.*?)```'
  )
  foreach ($rx in $regexes) {
    $m = [regex]::Match($Text, $rx)
    if ($m.Success -and $m.Groups.Count -gt 1) {
      return ($m.Groups[1].Value.Trim())
    }
  }
  # Si no hay fences, devuelve todo
  return $Text.Trim()
}

function Test-CodeSafety {
  param([Parameter(Mandatory)][string]$Code)
  if (-not $Global:LLM_PS_Config.SafeMode) { return $true }

  $dangerPatterns = @(
    '(?i)Remove-Item\s+.+-Recurse.+-Force',
    '(?i)Format-Volume',
    '(?i)Clear-Content\s+.+\\(Windows|System32)\\',
    '(?i)Disable-WindowsDefender',
    '(?i)Set-ExecutionPolicy\s+Unrestricted',
    '(?i)Stop-Service\s+-Name\s+.+\s+-Force',
    '(?i)Remove-Computer',
    '(?i)Invoke-WebRequest\s+.+\|\s*Invoke-Expression',
    '(?i)iex\s+'
  )
  foreach ($p in $dangerPatterns) {
    if ([regex]::IsMatch($Code, $p)) {
      Write-Warning "Bloqueado por patrón de seguridad: $p"
      return $false
    }
  }
  return $true
}

function Invoke-LLMPowerShell {
  <#
  .SYNOPSIS
    Genera código PowerShell desde lenguaje natural usando Ollama, y opcionalmente lo ejecuta.

  .PARAMETER Prompt
    Descripción en lenguaje natural de lo que necesitas.

  .PARAMETER Model
    Nombre del modelo de Ollama (ej. 'qwen2.5-coder:7b', 'llama3.1:8b-instruct').

  .PARAMETER Run
    Ejecuta el código generado tras mostrarlo (pasa los chequeos de seguridad básicos).

  .PARAMETER Stream
    Muestra la respuesta del modelo a medida que se genera.

  .EXAMPLE
    Invoke-LLMPowerShell -Prompt "Lista servicios que fallaron al iniciar y expórtalos a CSV" -Run
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Prompt,
    [string]$Model,
    [switch]$Run,
    [switch]$Stream
  )

  # 1) Arranque/chequeo de Ollama
  Install-OllamaIfNeeded
  Start-OllamaService
  Wait-Ollama

  # 2) Modelos disponibles
  if ($Model) {
    if (-not (Get-LLMModelsLocal | Where-Object { $_ -eq $Model })) {
      Write-Host "⬇️  Modelo no encontrado localmente. Descargando: $Model" -ForegroundColor Cyan
      Install-OllamaModels -Models @($Model)
    }
  } else {
    $Model = Select-AvailableModel
    if (-not (Get-LLMModelsLocal | Where-Object { $_ -eq $Model })) {
      Install-OllamaModels -Models @($Global:LLM_PS_Config.ModelsToPull)
      $Model = Select-AvailableModel
    }
  }

  Write-Host "🤖 Modelo: $Model" -ForegroundColor Green
  Write-Host "📝 Prompt: $Prompt" -ForegroundColor Green

  # 3) Llamada al LLM
  $raw = Invoke-OllamaGenerate -Model $Model -Prompt $Prompt -Stream:$Stream
  $code = Extract-PowerShellCode -Text $raw

  if ([string]::IsNullOrWhiteSpace($code)) {
    Write-Error "El modelo no devolvió código."
    return
  }

  Write-Host "================= CÓDIGO GENERADO (solo lectura) =================" -ForegroundColor Yellow
  Write-Host $code
  Write-Host "===================================================================" -ForegroundColor Yellow

  if ($Global:LLM_PS_Config.CopyToClipboard -and (Get-Command Set-Clipboard -ErrorAction SilentlyContinue)) {
    $code | Set-Clipboard
    Write-Host "📋 Copiado al portapapeles." -ForegroundColor Cyan
  }

  # 4) Ejecutar (opcional)
  $shouldRun = $Run.IsPresent -or $Global:LLM_PS_Config.DefaultRun
  if ($shouldRun) {
    if (-not (Test-CodeSafety -Code $code)) {
      Write-Error "Ejecución cancelada por reglas de seguridad. Revisa el código."
      return
    }
    try {
      Write-Host "▶️  Ejecutando código..." -ForegroundColor Cyan
      $scriptBlock = [ScriptBlock]::Create($code)
      & $scriptBlock
    } catch {
      Write-Error "Fallo al ejecutar el script generado: $($_.Exception.Message)"
    }
  } else {
    Write-Host "ℹ️  No se ejecuta automáticamente. Usa -Run o el alias 'ai! \"...\"' para ejecutar." -ForegroundColor DarkCyan
  }
}

# --- Aliases de uso rápido -----------------------------------------------------------
Set-Alias ai Invoke-LLMPowerShell
function ai! { param([Parameter(ValueFromRemainingArguments=$true)]$Args) Invoke-LLMPowerShell -Prompt ($Args -join ' ') -Run }

# --- Primer uso / preparación de modelos -------------------------------------------
try {
  Install-OllamaIfNeeded
  Start-OllamaService
  Wait-Ollama
  # Heurística por tu hardware: 32 GB RAM + RTX A2000 → 7B/8B en Q4-Q5 va fluido.
  Install-OllamaModels -Models $Global:LLM_PS_Config.ModelsToPull
  Write-Host "✅ Entorno listo. Prueba:  ai 'crea un script que liste servicios con estado Stopped y los exporte a CSV en el Escritorio'" -ForegroundColor Green
  Write-Host "   Para ejecutar directamente:  ai! 'lo mismo pero que borre archivos temporales con confirmación' " -ForegroundColor Green
} catch {
  Write-Warning $_
  Write-Warning "Puedes relanzar manualmente: Install-OllamaIfNeeded; Start-OllamaService; Wait-Ollama; Install-OllamaModels"
}
