#requires -Version 7.0
<#
.SYNOPSIS
Configura un stack AI híbrido para Windows + PowerShell:
- Ollama local optimizado para CPU/RAM moderada
- Modelos locales recomendados
- Wrappers para OpenAI, Gemini y Manus
- Salida bonita en terminal
- Alias listos para usar en terminal

.NOTES
Pensado para equipo tipo:
- Ryzen 7 5700U
- 12 GB RAM
- Sin GPU dedicada

Uso:
  pwsh -ExecutionPolicy Bypass -File .\Setup-AIStack.ps1
  pwsh -ExecutionPolicy Bypass -File .\Setup-AIStack.ps1 -SkipModelPull
#>

[CmdletBinding()]
param(
    [switch]$SkipModelPull,
    [switch]$SkipProfileUpdate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------
# Config
# ------------------------------------------------------------
$Config = [ordered]@{
    OllamaContextLength = 4096
    OllamaNumParallel   = 1
    OllamaMaxLoaded     = 1
    OllamaHost          = '127.0.0.1:11434'

    LocalReasonModel    = 'deepseek-r1:7b'
    LocalCodeModel      = 'qwen2.5-coder:7b'
    LocalChatModel      = 'llama3.1:8b'
    LocalVisionModel    = 'llava:7b'

    OpenAIModel         = 'gpt-5'
    GeminiModel         = 'gemini-2.5-flash'
    ManusAgentProfile   = 'manus-1.6'

    HttpTimeoutSec      = 300
}

# ------------------------------------------------------------
# Logging / UI
# ------------------------------------------------------------
function Write-Info  { param([string]$Message) Write-Host "[INFO]  $Message" -ForegroundColor Cyan }
function Write-Ok    { param([string]$Message) Write-Host "[OK]    $Message" -ForegroundColor Green }
function Write-Warn2 { param([string]$Message) Write-Host "[WARN]  $Message" -ForegroundColor Yellow }
function Write-Err2  { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
function Test-CommandExists {
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Set-UserEnv {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value
    )

    try {
        [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
        Set-Item -Path "Env:$Name" -Value $Value
    }
    catch {
        throw "No se pudo establecer la variable de entorno '$Name'. Detalle: $($_.Exception.Message)"
    }
}

function Get-ExceptionSummary {
    param([Parameter(Mandatory)]$ErrorRecord)

    $msg = $ErrorRecord.Exception.Message
    if ($ErrorRecord.ScriptStackTrace) {
        $msg += " | Stack: $($ErrorRecord.ScriptStackTrace)"
    }
    return $msg
}

function ConvertTo-JsonSafe {
    param(
        [Parameter(Mandatory)]$InputObject,
        [int]$Depth = 30
    )

    try {
        return ($InputObject | ConvertTo-Json -Depth $Depth -Compress)
    }
    catch {
        throw "No se pudo serializar JSON. Detalle: $($_.Exception.Message)"
    }
}

function Join-ArgText {
    param([string[]]$PromptArgs)

    if (-not $PromptArgs -or $PromptArgs.Count -eq 0) {
        throw 'Debes pasar un prompt.'
    }

    $text = ($PromptArgs -join ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw 'El prompt está vacío.'
    }

    return $text
}

function Get-ResponseText {
    param([Parameter(Mandatory)]$Response)

    if ($null -eq $Response) {
        return $null
    }

    if ($Response.PSObject.Properties.Name -contains 'output_text' -and $Response.output_text) {
        return [string]$Response.output_text
    }

    if ($Response.PSObject.Properties.Name -contains 'response' -and $Response.response) {
        return [string]$Response.response
    }

    $texts = New-Object System.Collections.Generic.List[string]

    if ($Response.PSObject.Properties.Name -contains 'output' -and $Response.output) {
        foreach ($item in $Response.output) {
            if ($null -eq $item) { continue }

            if ($item.PSObject.Properties.Name -contains 'content' -and $item.content) {
                foreach ($part in $item.content) {
                    if ($null -eq $part) { continue }

                    if ($part.PSObject.Properties.Name -contains 'text' -and $part.text) {
                        [void]$texts.Add([string]$part.text)
                    }
                }
            }
        }
    }

    if ($Response.PSObject.Properties.Name -contains 'message' -and $Response.message) {
        $msg = $Response.message
        if ($msg.PSObject.Properties.Name -contains 'content' -and $msg.content) {
            [void]$texts.Add([string]$msg.content)
        }
    }

    if ($Response.PSObject.Properties.Name -contains 'candidates' -and $Response.candidates) {
        foreach ($candidate in $Response.candidates) {
            if ($null -eq $candidate) { continue }

            if ($candidate.PSObject.Properties.Name -contains 'content' -and $candidate.content) {
                $content = $candidate.content
                if ($content.PSObject.Properties.Name -contains 'parts' -and $content.parts) {
                    foreach ($part in $content.parts) {
                        if ($null -eq $part) { continue }
                        if ($part.PSObject.Properties.Name -contains 'text' -and $part.text) {
                            [void]$texts.Add([string]$part.text)
                        }
                    }
                }
            }
        }
    }

    if ($texts.Count -gt 0) {
        return ($texts -join "`n").Trim()
    }

    try {
        return ($Response | ConvertTo-Json -Depth 20)
    }
    catch {
        return [string]$Response
    }
}

function Invoke-JsonApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('GET','POST','DELETE','PATCH','PUT')][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        [hashtable]$Headers,
        $Body,
        [int]$TimeoutSec = 120
    )

    try {
        $params = @{
            Uri         = $Uri
            Method      = $Method
            TimeoutSec  = $TimeoutSec
            ErrorAction = 'Stop'
        }

        if ($Headers) {
            $params.Headers = $Headers
        }

        if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
            $params.ContentType = 'application/json'
            $params.Body = if ($Body -is [string]) { $Body } else { ConvertTo-JsonSafe -InputObject $Body -Depth 30 }
        }

        return Invoke-RestMethod @params
    }
    catch {
        $detail = $_.Exception.Message
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
            $detail = "HTTP $([int]$_.Exception.Response.StatusCode) - $detail"
        }
        throw "Fallo en llamada API [$Method $Uri]. $detail"
    }
}

function Read-SecretLine {
    param([Parameter(Mandatory)][string]$Prompt)

    $secure = Read-Host -Prompt $Prompt -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)

    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Initialize-ApiKey {
    param(
        [Parameter(Mandatory)][string]$EnvName,
        [Parameter(Mandatory)][string]$PromptText
    )

    $userValue = [Environment]::GetEnvironmentVariable($EnvName, 'User')
    if (-not [string]::IsNullOrWhiteSpace($userValue)) {
        Set-Item -Path "Env:$EnvName" -Value $userValue
        Write-Ok "$EnvName ya existe en variables de usuario."
        return
    }

    $procValue = [Environment]::GetEnvironmentVariable($EnvName, 'Process')
    if (-not [string]::IsNullOrWhiteSpace($procValue)) {
        Write-Ok "$EnvName detectada en el entorno actual."
        return
    }

    $value = Read-SecretLine -Prompt "$PromptText (ENTER para omitir)"
    if (-not [string]::IsNullOrWhiteSpace($value)) {
        Set-UserEnv -Name $EnvName -Value $value
        Write-Ok "$EnvName guardada en variables de usuario."
    }
    else {
        Write-Warn2 "$EnvName no configurada."
    }
}

# ------------------------------------------------------------
# Pretty terminal output
# ------------------------------------------------------------
function Format-AIOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Title,
        [string]$Engine = "",
        [string]$Prompt = "",
        [int64]$ElapsedMs = 0,
        [ValidateSet('local','openai','gemini','manus','neutral','danger')]
        [string]$Theme = 'neutral'
    )

    $reset = $PSStyle.Reset
    $bold  = $PSStyle.Bold
    $dim   = $PSStyle.Dim

    switch ($Theme) {
        'local'  { $accent = $PSStyle.Foreground.BrightBlue;    $emoji = '🖥️' }
        'openai' { $accent = $PSStyle.Foreground.BrightGreen;   $emoji = '🧠' }
        'gemini' { $accent = $PSStyle.Foreground.BrightMagenta; $emoji = '✨'  }
        'manus'  { $accent = $PSStyle.Foreground.BrightYellow;  $emoji = '🛠️' }
        'danger' { $accent = $PSStyle.Foreground.BrightRed;     $emoji = '💥' }
        default  { $accent = $PSStyle.Foreground.BrightWhite;   $emoji = '🤖' }
    }

    $muted = $PSStyle.Foreground.BrightBlack
    $line  = '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'

    Write-Host ''
    Write-Host "$accent$bold$emoji $Title$reset"
    if ($Engine)          { Write-Host "$dim⚙️  Motor: $Engine$reset" }
    if ($ElapsedMs -gt 0) { Write-Host "$dim⏱️  Tiempo: $ElapsedMs ms$reset" }

    if (-not [string]::IsNullOrWhiteSpace($Prompt)) {
        Write-Host "$muted$line$reset"
        Write-Host "$bold📝 Prompt$reset"
        Write-Host "$dim$Prompt$reset"
    }

    Write-Host "$accent$line$reset"
    Write-Host "$bold📌 Respuesta$reset"
    Write-Host $Text
    Write-Host "$accent$line$reset"
    Write-Host ''
}

function Format-AICodeOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [string]$Engine = "",
        [string]$Prompt = "",
        [int64]$ElapsedMs = 0
    )

    $reset = $PSStyle.Reset
    $bold  = $PSStyle.Bold
    $cyan  = $PSStyle.Foreground.BrightCyan
    $dim   = $PSStyle.Dim
    $muted = $PSStyle.Foreground.BrightBlack
    $line  = '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'

    Write-Host ''
    Write-Host "$cyan$bold💻 Código generado$reset"
    if ($Engine)          { Write-Host "$dim⚙️  Motor: $Engine$reset" }
    if ($ElapsedMs -gt 0) { Write-Host "$dim⏱️  Tiempo: $ElapsedMs ms$reset" }

    if (-not [string]::IsNullOrWhiteSpace($Prompt)) {
        Write-Host "$muted$line$reset"
        Write-Host "$bold📝 Prompt$reset"
        Write-Host "$dim$Prompt$reset"
    }

    Write-Host "$cyan$line$reset"
    Write-Host $Text
    Write-Host "$cyan$line$reset"
    Write-Host ''
}

# ------------------------------------------------------------
# Ollama install / runtime
# ------------------------------------------------------------
function Install-Ollama {
    if (Test-CommandExists -Name 'ollama') {
        Write-Ok 'Ollama ya está instalado.'
        return
    }

    if (-not (Test-CommandExists -Name 'winget')) {
        throw 'No encuentro winget. Instala App Installer o usa el instalador oficial de Ollama.'
    }

    Write-Info 'Instalando Ollama con winget...'
    & winget install -e --id Ollama.Ollama --accept-package-agreements --accept-source-agreements
    Start-Sleep -Seconds 5

    if (-not (Test-CommandExists -Name 'ollama')) {
        $possible = @(
            "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe",
            "$env:ProgramFiles\Ollama\ollama.exe"
        ) | Where-Object { Test-Path $_ }

        if ($possible.Count -gt 0) {
            $dir = Split-Path -Path $possible[0] -Parent
            $env:Path = "$dir;$env:Path"
        }
    }

    if (-not (Test-CommandExists -Name 'ollama')) {
        throw 'Ollama parece instalado pero no está en PATH todavía. Cierra y abre PowerShell y vuelve a ejecutar el script.'
    }

    Write-Ok 'Ollama instalado.'
}

function Set-OllamaTuning {
    Write-Info 'Aplicando tuning de Ollama para tu equipo...'
    Set-UserEnv -Name 'OLLAMA_CONTEXT_LENGTH'    -Value ([string]$Config.OllamaContextLength)
    Set-UserEnv -Name 'OLLAMA_NUM_PARALLEL'      -Value ([string]$Config.OllamaNumParallel)
    Set-UserEnv -Name 'OLLAMA_MAX_LOADED_MODELS' -Value ([string]$Config.OllamaMaxLoaded)
    Set-UserEnv -Name 'OLLAMA_HOST'              -Value $Config.OllamaHost
    Write-Ok 'Variables de entorno de Ollama configuradas.'
}

function Test-OllamaResponsive {
    try {
        $null = Invoke-JsonApi -Method GET -Uri "http://$($Config.OllamaHost)/api/tags" -TimeoutSec 5
        return $true
    }
    catch {
        return $false
    }
}

function Start-Ollama {
    Write-Info 'Comprobando si Ollama responde...'

    if (Test-OllamaResponsive) {
        Write-Ok "Ollama ya responde en http://$($Config.OllamaHost)"
        return
    }

    Write-Warn2 'Ollama no responde todavía. Intentando arrancarlo...'

    $paths = @(
        "$env:LOCALAPPDATA\Programs\Ollama\ollama app.exe",
        "$env:ProgramFiles\Ollama\ollama app.exe",
        "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe",
        "$env:ProgramFiles\Ollama\ollama.exe"
    ) | Where-Object { Test-Path $_ }

    if ($paths.Count -gt 0) {
        try {
            Start-Process -FilePath $paths[0] | Out-Null
            Start-Sleep -Seconds 8
        }
        catch {
            Write-Warn2 "No pude arrancar Ollama automáticamente. Detalle: $($_.Exception.Message)"
        }
    }

    if (-not (Test-OllamaResponsive)) {
        Write-Warn2 "No he conseguido confirmar que Ollama esté escuchando en http://$($Config.OllamaHost)"
    }
    else {
        Write-Ok 'Ollama arrancado.'
    }
}

function Get-OllamaTags {
    if (-not (Test-OllamaResponsive)) {
        throw 'Ollama no responde. No puedo consultar modelos.'
    }

    return Invoke-JsonApi -Method GET -Uri "http://$($Config.OllamaHost)/api/tags" -TimeoutSec 15
}

function Install-OllamaModel {
    param([Parameter(Mandatory)][string]$Model)

    Write-Info "Comprobando modelo $Model ..."
    $tags = Get-OllamaTags
    $exists = $false

    if ($tags.models) {
        $names = @($tags.models | ForEach-Object { $_.name })
        $exists = $names -contains $Model
    }

    if ($exists) {
        Write-Ok "Modelo ya disponible: $Model"
        return
    }

    Write-Info "Descargando modelo: $Model"
    try {
        & ollama pull $Model
        if ($LASTEXITCODE -ne 0) {
            throw "ollama pull devolvió código $LASTEXITCODE"
        }
    }
    catch {
        throw "No se pudo descargar el modelo '$Model'. Detalle: $($_.Exception.Message)"
    }

    Write-Ok "Modelo descargado: $Model"
}

# ------------------------------------------------------------
# Hardware & Model Recommendation
# ------------------------------------------------------------
function Get-HardwareProfile {
    Write-Info 'Detectando perfil de hardware del equipo...'
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $ram = Get-CimInstance Win32_ComputerSystem | Select-Object -First 1
    $gpus = Get-CimInstance Win32_VideoController

    $cpuName = if ($cpu) { $cpu.Name } else { 'Desconocido' }
    $ramGB = if ($ram) { [math]::Round($ram.TotalPhysicalMemory / 1GB, 1) } else { 0 }
    
    $vramTotal = 0
    if ($gpus) {
        foreach ($gpu in $gpus) {
            if ($gpu.AdapterRAM) {
                $vramTotal += $gpu.AdapterRAM
            }
        }
    }
    $vramGB = [math]::Round($vramTotal / 1GB, 1)
    
    $profile = [ordered]@{
        CPU  = $cpuName
        RAM  = "$ramGB"
        VRAM = "$vramGB"
    }

    Write-Ok "Hardware: $($profile.CPU) | RAM: $($profile.RAM) GB | VRAM: $($profile.VRAM) GB"
    return $profile
}

function Get-RecommendedModels {
    param([Parameter(Mandatory)]$HardwareProfile)

    Write-Info 'Determinando los mejores modelos de Ollama para este equipo...'

    $prompt = @"
Eres un experto en IA local (Ollama). 
El equipo actual tiene las siguientes especificaciones:
- CPU: $($HardwareProfile.CPU)
- RAM: $($HardwareProfile.RAM) GB
- VRAM (Video RAM): $($HardwareProfile.VRAM) GB

Recomienda los mejores modelos de Ollama para 4 categorías:
1. "LocalReasonModel": Modelo de razonamiento (ej. deepseek-r1:1.5b/7b/8b/14b).
2. "LocalCodeModel": Modelo de código (ej. qwen2.5-coder:1.5b/7b).
3. "LocalChatModel": Modelo de chat general (ej. llama3.2:3b, llama3.1:8b).
4. "LocalVisionModel": Modelo de visión (ej. llava, llama3.2-vision).

Reglas:
- Si RAM+VRAM es bajo (ej. < 8GB), recomienda modelos muy pequeños (1.5B a 3B).
- Si RAM es ~12-16GB o hay VRAM >4GB, recomienda modelos de 7B u 8B.
- Si RAM > 24GB, puedes sugerir modelos de 14B o 32B.
Responde ÚNICAMENTE con un JSON válido con estas claves exactas y el nombre del modelo recomendado como valor (sin markdown ni texto extra).
"@

    $jsonResponse = $null

    if ($env:GEMINI_API_KEY -or $env:GOOGLE_API_KEY) {
        $apiKey = if ($env:GEMINI_API_KEY) { $env:GEMINI_API_KEY } else { $env:GOOGLE_API_KEY }
        try {
            Write-Info 'Consultando a Gemini para recomendación dinámica...'
            $body = @{
                contents = @( @{ parts = @( @{ text = $prompt } ) } )
                system_instruction = @{ parts = @( @{ text = 'Responde sólo en JSON puro' } ) }
            }
            $uri = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey"
            $resp = Invoke-JsonApi -Method POST -Uri $uri -Body $body -TimeoutSec 30
            $jsonResponse = Get-ResponseText -Response $resp
        } catch { Write-Warn2 "Fallo al consultar Gemini: $_" }
    }
    
    if (-not $jsonResponse -and $env:OPENAI_API_KEY) {
        try {
            Write-Info 'Consultando a OpenAI para recomendación dinámica...'
            $body = @{
                model = "gpt-4o-mini"
                messages = @(
                    @{ role = 'system'; content = 'Responde sólo en JSON puro' },
                    @{ role = 'user'; content = $prompt }
                )
            }
            $resp = Invoke-JsonApi -Method POST -Uri 'https://api.openai.com/v1/chat/completions' -Headers @{ Authorization = "Bearer $($env:OPENAI_API_KEY)" } -Body $body -TimeoutSec 30
            
            if ($resp.choices -and $resp.choices[0].message.content) {
                $jsonResponse = $resp.choices[0].message.content
            }
        } catch { Write-Warn2 "Fallo al consultar OpenAI: $_" }
    }

    if ($jsonResponse) {
        $jsonResponse = $jsonResponse -replace '(?s)^```json\s*', '' -replace '(?s)\s*```$', ''
        try {
            $rec = $jsonResponse | ConvertFrom-Json
            if ($rec.LocalReasonModel) {
                Write-Ok 'Recomendación dinámica obtenida con IA.'
                return $rec
            }
        } catch {
            Write-Warn2 "El JSON de la IA no era válido o faltaban claves. Usando fallback estático."
        }
    } else {
        Write-Info 'Sin conexión a IA o configuración incompleta. Usando tabla de recomendación estática (fallback)...'
    }

    $ramNum = [double]$HardwareProfile.RAM
    $vramNum = [double]$HardwareProfile.VRAM
    $totalMem = $ramNum + $vramNum

    if ($totalMem -lt 10) {
        return [pscustomobject]@{
            LocalReasonModel = 'deepseek-r1:1.5b'
            LocalCodeModel   = 'qwen2.5-coder:1.5b'
            LocalChatModel   = 'llama3.2:3b'
            LocalVisionModel = 'llava:7b'
        }
    } elseif ($totalMem -lt 24) {
        return [pscustomobject]@{
            LocalReasonModel = 'deepseek-r1:7b'
            LocalCodeModel   = 'qwen2.5-coder:7b'
            LocalChatModel   = 'llama3.1:8b'
            LocalVisionModel = 'llava:7b'
        }
    } else {
        return [pscustomobject]@{
            LocalReasonModel = 'deepseek-r1:14b'
            LocalCodeModel   = 'qwen2.5-coder:14b'
            LocalChatModel   = 'llama3.1:8b'
            LocalVisionModel = 'llama3.2-vision:11b'
        }
    }
}

# ------------------------------------------------------------
# Cloud keys
# ------------------------------------------------------------
function Initialize-CloudApiKeys {
    Write-Host ''
    Write-Info 'Configuración de claves cloud'

    if ($env:OPENAI_API_KEY) {
        Write-Ok 'OPENAI_API_KEY detectada en el entorno actual.'
    }
    else {
        Initialize-ApiKey -EnvName 'OPENAI_API_KEY' -PromptText 'Introduce OPENAI_API_KEY'
    }

    if ($env:GEMINI_API_KEY) {
        Write-Ok 'GEMINI_API_KEY detectada en el entorno actual.'
    }
    elseif ($env:GOOGLE_API_KEY) {
        Set-UserEnv -Name 'GEMINI_API_KEY' -Value $env:GOOGLE_API_KEY
        Write-Ok 'He reutilizado GOOGLE_API_KEY como GEMINI_API_KEY.'
    }
    else {
        Initialize-ApiKey -EnvName 'GEMINI_API_KEY' -PromptText 'Introduce GEMINI_API_KEY o GOOGLE_API_KEY'
    }

    if ($env:MANUS_API_KEY) {
        Write-Ok 'MANUS_API_KEY detectada en el entorno actual.'
    }
    else {
        Write-Warn2 'MANUS_API_KEY no encontrada. ai-manus quedará disponible solo cuando la configures.'
    }
}

# ------------------------------------------------------------
# Profile block
# ------------------------------------------------------------
function Build-ProfileBlock {
@"
# >>> AI STACK START >>>
`$global:OllamaChatContext      = `$null
`$global:OllamaMessages         = @()
`$env:OLLAMA_CONTEXT_LENGTH     = "$($Config.OllamaContextLength)"
`$env:OLLAMA_NUM_PARALLEL       = "$($Config.OllamaNumParallel)"
`$env:OLLAMA_MAX_LOADED_MODELS  = "$($Config.OllamaMaxLoaded)"
`$env:OLLAMA_HOST               = "$($Config.OllamaHost)"

function ConvertTo-JsonSafe {
    param(
        [Parameter(Mandatory)] `$InputObject,
        [int] `$Depth = 30
    )
    try {
        return (`$InputObject | ConvertTo-Json -Depth `$Depth -Compress)
    }
    catch {
        throw "No se pudo serializar JSON. Detalle: `$(`$_.Exception.Message)"
    }
}

function Join-ArgText {
    param([string[]]`$PromptArgs)

    if (-not `$PromptArgs -or `$PromptArgs.Count -eq 0) {
        throw 'Debes pasar un prompt.'
    }

    `$text = (`$PromptArgs -join ' ').Trim()
    if ([string]::IsNullOrWhiteSpace(`$text)) {
        throw 'El prompt está vacío.'
    }

    return `$text
}

function Get-AIResponseText {
    param([Parameter(Mandatory)] `$Response)

    if (`$null -eq `$Response) {
        return `$null
    }

    if (`$Response.PSObject.Properties.Name -contains 'output_text' -and `$Response.output_text) {
        return [string]`$Response.output_text
    }

    if (`$Response.PSObject.Properties.Name -contains 'response' -and `$Response.response) {
        return [string]`$Response.response
    }

    `$texts = New-Object System.Collections.Generic.List[string]

    if (`$Response.PSObject.Properties.Name -contains 'output' -and `$Response.output) {
        foreach (`$item in `$Response.output) {
            if (`$null -eq `$item) { continue }

            if (`$item.PSObject.Properties.Name -contains 'content' -and `$item.content) {
                foreach (`$part in `$item.content) {
                    if (`$null -eq `$part) { continue }

                    if (`$part.PSObject.Properties.Name -contains 'text' -and `$part.text) {
                        [void]`$texts.Add([string]`$part.text)
                    }
                }
            }
        }
    }

    if (`$Response.PSObject.Properties.Name -contains 'message' -and `$Response.message) {
        `$msg = `$Response.message
        if (`$msg.PSObject.Properties.Name -contains 'content' -and `$msg.content) {
            [void]`$texts.Add([string]`$msg.content)
        }
    }

    if (`$Response.PSObject.Properties.Name -contains 'candidates' -and `$Response.candidates) {
        foreach (`$candidate in `$Response.candidates) {
            if (`$null -eq `$candidate) { continue }

            if (`$candidate.PSObject.Properties.Name -contains 'content' -and `$candidate.content) {
                `$content = `$candidate.content
                if (`$content.PSObject.Properties.Name -contains 'parts' -and `$content.parts) {
                    foreach (`$part in `$content.parts) {
                        if (`$null -eq `$part) { continue }
                        if (`$part.PSObject.Properties.Name -contains 'text' -and `$part.text) {
                            [void]`$texts.Add([string]`$part.text)
                        }
                    }
                }
            }
        }
    }

    if (`$texts.Count -gt 0) {
        return (`$texts -join "`n").Trim()
    }

    try {
        return (`$Response | ConvertTo-Json -Depth 20)
    }
    catch {
        return [string]`$Response
    }
}

function Invoke-JsonApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('GET','POST','DELETE','PATCH','PUT')][string]`$Method,
        [Parameter(Mandatory)][string]`$Uri,
        [hashtable]`$Headers,
        `$Body,
        [int]`$TimeoutSec = 120
    )

    try {
        `$params = @{
            Uri         = `$Uri
            Method      = `$Method
            TimeoutSec  = `$TimeoutSec
            ErrorAction = 'Stop'
        }

        if (`$Headers) {
            `$params.Headers = `$Headers
        }

        if (`$PSBoundParameters.ContainsKey('Body') -and `$null -ne `$Body) {
            `$params.ContentType = 'application/json'
            `$params.Body = if (`$Body -is [string]) { `$Body } else { ConvertTo-JsonSafe -InputObject `$Body -Depth 30 }
        }

        return Invoke-RestMethod @params
    }
    catch {
        `$detail = `$_.Exception.Message
        if (`$_.Exception.Response -and `$_.Exception.Response.StatusCode) {
            `$detail = "HTTP `$([int]`$_.Exception.Response.StatusCode) - `$detail"
        }
        throw "Fallo en llamada API [`$Method `$Uri]. `$detail"
    }
}

function Test-OllamaAlive {
    try {
        `$null = Invoke-JsonApi -Method GET -Uri "http://`$env:OLLAMA_HOST/api/tags" -TimeoutSec 5
        return `$true
    }
    catch {
        return `$false
    }
}

function Assert-OllamaAlive {
    if (-not (Test-OllamaAlive)) {
        throw "Ollama no responde en http://`$env:OLLAMA_HOST"
    }
}

function Format-AIOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]`$Text,
        [Parameter(Mandatory)][string]`$Title,
        [string]`$Engine = '',
        [string]`$Prompt = '',
        [int64]`$ElapsedMs = 0,
        [ValidateSet('local','openai','gemini','manus','neutral','danger')]
        [string]`$Theme = 'neutral'
    )

    `$reset = `$PSStyle.Reset
    `$bold  = `$PSStyle.Bold
    `$dim   = `$PSStyle.Dim

    switch (`$Theme) {
        'local'  { `$accent = `$PSStyle.Foreground.BrightBlue;    `$emoji = '🖥️' }
        'openai' { `$accent = `$PSStyle.Foreground.BrightGreen;   `$emoji = '🧠' }
        'gemini' { `$accent = `$PSStyle.Foreground.BrightMagenta; `$emoji = '✨'  }
        'manus'  { `$accent = `$PSStyle.Foreground.BrightYellow;  `$emoji = '🛠️' }
        'danger' { `$accent = `$PSStyle.Foreground.BrightRed;     `$emoji = '💥' }
        default  { `$accent = `$PSStyle.Foreground.BrightWhite;   `$emoji = '🤖' }
    }

    `$muted = `$PSStyle.Foreground.BrightBlack
    `$line  = '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'

    Write-Host ''
    Write-Host "`$accent`$bold`$emoji `$Title`$reset"
    if (`$Engine)          { Write-Host "`$dim⚙️  Motor: `$Engine`$reset" }
    if (`$ElapsedMs -gt 0) { Write-Host "`$dim⏱️  Tiempo: `$ElapsedMs ms`$reset" }

    if (-not [string]::IsNullOrWhiteSpace(`$Prompt)) {
        Write-Host "`$muted`$line`$reset"
        Write-Host "`$bold📝 Prompt`$reset"
        Write-Host "`$dim`$Prompt`$reset"
    }

    Write-Host "`$accent`$line`$reset"
    Write-Host "`$bold📌 Respuesta`$reset"
    Write-Host `$Text
    Write-Host "`$accent`$line`$reset"
    Write-Host ''
}

function Format-AICodeOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]`$Text,
        [string]`$Engine = '',
        [string]`$Prompt = '',
        [int64]`$ElapsedMs = 0
    )

    `$reset = `$PSStyle.Reset
    `$bold  = `$PSStyle.Bold
    `$cyan  = `$PSStyle.Foreground.BrightCyan
    `$dim   = `$PSStyle.Dim
    `$muted = `$PSStyle.Foreground.BrightBlack
    `$line  = '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'

    Write-Host ''
    Write-Host "`$cyan`$bold💻 Código generado`$reset"
    if (`$Engine)          { Write-Host "`$dim⚙️  Motor: `$Engine`$reset" }
    if (`$ElapsedMs -gt 0) { Write-Host "`$dim⏱️  Tiempo: `$ElapsedMs ms`$reset" }

    if (-not [string]::IsNullOrWhiteSpace(`$Prompt)) {
        Write-Host "`$muted`$line`$reset"
        Write-Host "`$bold📝 Prompt`$reset"
        Write-Host "`$dim`$Prompt`$reset"
    }

    Write-Host "`$cyan`$line`$reset"
    Write-Host `$Text
    Write-Host "`$cyan`$line`$reset"
    Write-Host ''
}

function Invoke-OllamaLocal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]`$Prompt,
        [string]`$Model = "$($Config.LocalChatModel)",
        [string]`$System = '',
        [int]`$NumCtx = $($Config.OllamaContextLength),
        [double]`$Temperature = 0.2
    )

    Assert-OllamaAlive
    `$sw = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        if (`$null -eq `$global:OllamaMessages) {
            `$global:OllamaMessages = @()
        }

        if (`$global:OllamaMessages.Count -eq 0 -and (-not [string]::IsNullOrWhiteSpace(`$System))) {
            `$global:OllamaMessages += @{ role = 'system'; content = `$System }
        }

        `$global:OllamaMessages += @{ role = 'user'; content = `$Prompt }

        `$body = @{
            model    = `$Model
            messages = `$global:OllamaMessages
            stream   = `$false
            options  = @{
                num_ctx     = `$NumCtx
                temperature = `$Temperature
            }
        }

        `$resp = Invoke-JsonApi -Method POST -Uri "http://`$env:OLLAMA_HOST/api/chat" -Body `$body -TimeoutSec 300
        `$text = Get-AIResponseText -Response `$resp

        if ([string]::IsNullOrWhiteSpace(`$text)) {
            throw 'Ollama devolvió respuesta vacía.'
        }

        `$global:OllamaMessages += @{ role = 'assistant'; content = `$text }

        return [pscustomobject]@{
            Text      = `$text
            Engine    = "Ollama · `$Model"
            Theme     = 'local'
            ElapsedMs = `$sw.ElapsedMilliseconds
        }
    }
    finally {
        `$sw.Stop()
    }
}

function Invoke-OpenAIText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]`$Prompt,
        [string]`$Model = "$($Config.OpenAIModel)",
        [string]`$Instructions = ''
    )

    if ([string]::IsNullOrWhiteSpace(`$Prompt)) {
        throw 'El prompt para OpenAI está vacío.'
    }

    if (-not `$env:OPENAI_API_KEY) {
        throw 'Falta OPENAI_API_KEY'
    }

    `$sw = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        `$body = @{
            model = `$Model
            input = `$Prompt
        }

        if (-not [string]::IsNullOrWhiteSpace(`$Instructions)) {
            `$body.instructions = `$Instructions
        }

        `$resp = Invoke-JsonApi -Method POST -Uri 'https://api.openai.com/v1/responses' -Headers @{ Authorization = "Bearer `$env:OPENAI_API_KEY" } -Body `$body -TimeoutSec 300
        `$text = Get-AIResponseText -Response `$resp

        if ([string]::IsNullOrWhiteSpace(`$text)) {
            throw 'OpenAI devolvió respuesta vacía.'
        }

        return [pscustomobject]@{
            Text      = `$text
            Engine    = "OpenAI · `$Model"
            Theme     = 'openai'
            ElapsedMs = `$sw.ElapsedMilliseconds
        }
    }
    finally {
        `$sw.Stop()
    }
}

function Invoke-GeminiText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]`$Prompt,
        [string]`$Model = "$($Config.GeminiModel)",
        [string]`$System = ''
    )

    if ([string]::IsNullOrWhiteSpace(`$Prompt)) {
        throw 'El prompt para Gemini está vacío.'
    }

    `$apiKey = `$env:GEMINI_API_KEY
    if (-not `$apiKey) { `$apiKey = `$env:GOOGLE_API_KEY }

    if (-not `$apiKey) {
        throw 'Falta GEMINI_API_KEY o GOOGLE_API_KEY'
    }

    `$sw = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        `$body = @{
            contents = @(
                @{
                    parts = @(
                        @{ text = `$Prompt }
                    )
                }
            )
        }

        if (-not [string]::IsNullOrWhiteSpace(`$System)) {
            `$body.system_instruction = @{
                parts = @(
                    @{ text = `$System }
                )
            }
        }

        `$uri = "https://generativelanguage.googleapis.com/v1beta/models/`${Model}:generateContent?key=`$apiKey"
        `$uri = `$ExecutionContext.InvokeCommand.ExpandString(`$uri)

        `$resp = Invoke-JsonApi -Method POST -Uri `$uri -Body `$body -TimeoutSec 300
        `$text = Get-AIResponseText -Response `$resp

        if ([string]::IsNullOrWhiteSpace(`$text)) {
            throw 'Gemini devolvió una respuesta sin texto utilizable.'
        }

        return [pscustomobject]@{
            Text      = `$text
            Engine    = "Gemini · `$Model"
            Theme     = 'gemini'
            ElapsedMs = `$sw.ElapsedMilliseconds
        }
    }
    finally {
        `$sw.Stop()
    }
}

function Invoke-ManusText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]`$Prompt,
        [string]`$AgentProfile = "$($Config.ManusAgentProfile)",
        [int]`$PollEverySeconds = 5,
        [int]`$TimeoutSeconds = 600
    )

    if ([string]::IsNullOrWhiteSpace(`$Prompt)) {
        throw 'El prompt para Manus está vacío.'
    }

    if (-not `$env:MANUS_API_KEY) {
        throw 'Falta MANUS_API_KEY'
    }

    `$sw = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        `$createBody = @{
            input = @(
                @{
                    role = 'user'
                    content = @(
                        @{
                            type = 'input_text'
                            text = `$Prompt
                        }
                    )
                }
            )
            extra_body = @{
                task_mode = 'agent'
                agent_profile = `$AgentProfile
            }
        }

        `$headers = @{ API_KEY = `$env:MANUS_API_KEY }
        `$createResp = Invoke-JsonApi -Method POST -Uri 'https://api.manus.im/v1/responses' -Headers `$headers -Body `$createBody -TimeoutSec 120

        if (-not `$createResp.id) {
            throw 'Manus no devolvió id de tarea.'
        }

        `$id = `$createResp.id
        `$deadline = (Get-Date).AddSeconds(`$TimeoutSeconds)
        `$statusResp = `$null

        do {
            Start-Sleep -Seconds `$PollEverySeconds
            `$statusResp = Invoke-JsonApi -Method GET -Uri "https://api.manus.im/v1/responses/`$id" -Headers `$headers -TimeoutSec 120

            switch (`$statusResp.status) {
                'completed' {
                    `$text = Get-AIResponseText -Response `$statusResp
                    if (-not [string]::IsNullOrWhiteSpace(`$text)) {
                        return [pscustomobject]@{
                            Text      = `$text
                            Engine    = "Manus · `$AgentProfile"
                            Theme     = 'manus'
                            ElapsedMs = `$sw.ElapsedMilliseconds
                        }
                    }
                    throw 'Manus terminó pero no devolvió texto utilizable.'
                }
                'pending' {
                    if (`$statusResp.metadata.task_url) {
                        return [pscustomobject]@{
                            Text      = "La tarea Manus quedó en estado pending y espera más interacción. Task URL: `$(`$statusResp.metadata.task_url)"
                            Engine    = "Manus · `$AgentProfile"
                            Theme     = 'manus'
                            ElapsedMs = `$sw.ElapsedMilliseconds
                        }
                    }

                    return [pscustomobject]@{
                        Text      = 'La tarea Manus quedó en estado pending y espera más interacción.'
                        Engine    = "Manus · `$AgentProfile"
                        Theme     = 'manus'
                        ElapsedMs = `$sw.ElapsedMilliseconds
                    }
                }
                'error' {
                    if (`$statusResp.metadata.task_url) {
                        throw "La tarea Manus terminó con error. Task URL: `$(`$statusResp.metadata.task_url)"
                    }
                    throw 'La tarea Manus terminó con error.'
                }
            }
        } while ((Get-Date) -lt `$deadline)

        if (`$statusResp -and `$statusResp.metadata.task_url) {
            return [pscustomobject]@{
                Text      = "Timeout esperando a Manus. Revisa la tarea en: `$(`$statusResp.metadata.task_url)"
                Engine    = "Manus · `$AgentProfile"
                Theme     = 'manus'
                ElapsedMs = `$sw.ElapsedMilliseconds
            }
        }

        return [pscustomobject]@{
            Text      = 'Timeout esperando a Manus.'
            Engine    = "Manus · `$AgentProfile"
            Theme     = 'manus'
            ElapsedMs = `$sw.ElapsedMilliseconds
        }
    }
    finally {
        `$sw.Stop()
    }
}

function Start-CaptiveChat {
    param(
        [string]`$Title,
        [string[]]`$InitialPromptArgs,
        [scriptblock]`$Action
    )

    Write-Host "`n=========================================" -ForegroundColor Cyan
    Write-Host " `$Title " -ForegroundColor Cyan
    Write-Host " Escribe 'salir', 'quit' o 'bye' para terminar." -ForegroundColor DarkGray
    Write-Host "=========================================`n" -ForegroundColor Cyan

    `$firstPrompt = `$null
    if (`$InitialPromptArgs -and `$InitialPromptArgs.Count -gt 0) {
        `$firstPrompt = (`$InitialPromptArgs -join ' ').Trim()
    }

    while (`$true) {
        if (`$firstPrompt) {
            `$userInput = `$firstPrompt
            Write-Host "Tú: `$userInput" -ForegroundColor White
            `$firstPrompt = `$null
        } else {
            `$userInput = Read-Host -Prompt "Tú"
        }

        if ([string]::IsNullOrWhiteSpace(`$userInput)) { continue }
        `$lower = `$userInput.Trim().ToLower()
        if (`$lower -match "^(salir|quit|exit|bye)$") {
            Write-Host "`nSesión finalizada. ¡Hasta luego!`n" -ForegroundColor Green
            break
        }

        try {
            & `$Action `$userInput
        }
        catch {
            Write-Host "`n[ERROR] `$(`$_.Exception.Message)`n" -ForegroundColor Red
        }
    }
}

function ai-local {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments=`$true)][string[]]`$PromptArgs)
    Start-CaptiveChat -Title "Chat Interactivo (Razonamiento Local)" -InitialPromptArgs `$PromptArgs -Action {
        param(`$p)
        `$result = Invoke-OllamaLocal -Prompt `$p -Model "$($Config.LocalReasonModel)" -System 'Responde en español, directo, útil y sin relleno.'
        Format-AIOutput -Text `$result.Text -Title 'IA' -Engine `$result.Engine -ElapsedMs `$result.ElapsedMs -Theme `$result.Theme
    }
}

function ai-code {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments=`$true)][string[]]`$PromptArgs)
    Start-CaptiveChat -Title "Chat Interactivo (Código Local)" -InitialPromptArgs `$PromptArgs -Action {
        param(`$p)
        `$result = Invoke-OllamaLocal -Prompt `$p -Model "$($Config.LocalCodeModel)" -System 'Eres experto en programación. Da soluciones exactas.'
        Format-AICodeOutput -Text `$result.Text -Engine `$result.Engine -ElapsedMs `$result.ElapsedMs
    }
}

function ai-chat {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments=`$true)][string[]]`$PromptArgs)
    Start-CaptiveChat -Title "Chat Interactivo (Chat Local)" -InitialPromptArgs `$PromptArgs -Action {
        param(`$p)
        `$result = Invoke-OllamaLocal -Prompt `$p -Model "$($Config.LocalChatModel)" -System 'Responde en español de forma natural, clara y directa.'
        Format-AIOutput -Text `$result.Text -Title 'IA' -Engine `$result.Engine -ElapsedMs `$result.ElapsedMs -Theme `$result.Theme
    }
}

function ai-openai {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments=`$true)][string[]]`$PromptArgs)
    Start-CaptiveChat -Title "Chat Interactivo (OpenAI)" -InitialPromptArgs `$PromptArgs -Action {
        param(`$p)
        `$result = Invoke-OpenAIText -Prompt `$p -Instructions 'Responde en español, con rigor, directo y sin inventar.'
        if (`$null -eq `$result) { throw 'OpenAI no devolvió objeto de resultado.' }
        Format-AIOutput -Text `$result.Text -Title 'IA' -Engine `$result.Engine -ElapsedMs `$result.ElapsedMs -Theme `$result.Theme
    }
}

function ai-gemini {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments=`$true)][string[]]`$PromptArgs)
    Start-CaptiveChat -Title "Chat Interactivo (Gemini)" -InitialPromptArgs `$PromptArgs -Action {
        param(`$p)
        `$result = Invoke-GeminiText -Prompt `$p -System 'Responde en español, directo, útil y preciso.'
        if (`$null -eq `$result) { throw 'Gemini no devolvió objeto de resultado.' }
        Format-AIOutput -Text `$result.Text -Title 'IA' -Engine `$result.Engine -ElapsedMs `$result.ElapsedMs -Theme `$result.Theme
    }
}

function ai-manus {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments=`$true)][string[]]`$PromptArgs)
    Start-CaptiveChat -Title "Chat Interactivo (Manus)" -InitialPromptArgs `$PromptArgs -Action {
        param(`$p)
        `$result = Invoke-ManusText -Prompt `$p
        if (`$null -eq `$result) { throw 'Manus no devolvió objeto de resultado.' }
        Format-AIOutput -Text `$result.Text -Title 'IA' -Engine `$result.Engine -ElapsedMs `$result.ElapsedMs -Theme `$result.Theme
    }
}

function ai-router {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]`$Prompt,
        [ValidateSet('reason','code','chat','research')]
        [string]`$Task = 'chat'
    )

    if ([string]::IsNullOrWhiteSpace(`$Prompt)) {
        throw 'El prompt está vacío.'
    }

    switch (`$Task) {
        'code' {
            if (`$Prompt.Length -lt 2500) {
                `$result = Invoke-OllamaLocal -Prompt `$Prompt -Model "$($Config.LocalCodeModel)" -System 'Responde en español. Código primero.'
                Format-AICodeOutput -Text `$result.Text -Engine `$result.Engine -Prompt `$Prompt -ElapsedMs `$result.ElapsedMs
                return
            }

            if (`$env:OPENAI_API_KEY) {
                `$result = Invoke-OpenAIText -Prompt `$Prompt -Instructions 'Responde en español. Código primero.'
                Format-AICodeOutput -Text `$result.Text -Engine `$result.Engine -Prompt `$Prompt -ElapsedMs `$result.ElapsedMs
                return
            }

            if (`$env:GEMINI_API_KEY -or `$env:GOOGLE_API_KEY) {
                `$result = Invoke-GeminiText -Prompt `$Prompt -System 'Responde en español. Código primero.'
                Format-AICodeOutput -Text `$result.Text -Engine `$result.Engine -Prompt `$Prompt -ElapsedMs `$result.ElapsedMs
                return
            }

            `$result = Invoke-OllamaLocal -Prompt `$Prompt -Model "$($Config.LocalCodeModel)" -System 'Responde en español. Código primero.'
            Format-AICodeOutput -Text `$result.Text -Engine `$result.Engine -Prompt `$Prompt -ElapsedMs `$result.ElapsedMs
            return
        }

        'reason' {
            if (`$Prompt.Length -lt 1800) {
                `$result = Invoke-OllamaLocal -Prompt `$Prompt -Model "$($Config.LocalReasonModel)" -System 'Responde en español, directo y razonado.'
                Format-AIOutput -Text `$result.Text -Title 'Razonamiento' -Engine `$result.Engine -Prompt `$Prompt -ElapsedMs `$result.ElapsedMs -Theme `$result.Theme
                return
            }

            if (`$env:MANUS_API_KEY) {
                `$result = Invoke-ManusText -Prompt `$Prompt
                Format-AIOutput -Text `$result.Text -Title 'Razonamiento' -Engine `$result.Engine -Prompt `$Prompt -ElapsedMs `$result.ElapsedMs -Theme `$result.Theme
                return
            }

            if (`$env:OPENAI_API_KEY) {
                `$result = Invoke-OpenAIText -Prompt `$Prompt -Instructions 'Responde en español, directo y razonado.'
                Format-AIOutput -Text `$result.Text -Title 'Razonamiento' -Engine `$result.Engine -Prompt `$Prompt -ElapsedMs `$result.ElapsedMs -Theme `$result.Theme
                return
            }

            if (`$env:GEMINI_API_KEY -or `$env:GOOGLE_API_KEY) {
                `$result = Invoke-GeminiText -Prompt `$Prompt -System 'Responde en español, directo y razonado.'
                Format-AIOutput -Text `$result.Text -Title 'Razonamiento' -Engine `$result.Engine -Prompt `$Prompt -ElapsedMs `$result.ElapsedMs -Theme `$result.Theme
                return
            }

            `$result = Invoke-OllamaLocal -Prompt `$Prompt -Model "$($Config.LocalReasonModel)" -System 'Responde en español, directo y razonado.'
            Format-AIOutput -Text `$result.Text -Title 'Razonamiento' -Engine `$result.Engine -Prompt `$Prompt -ElapsedMs `$result.ElapsedMs -Theme `$result.Theme
            return
        }

        'research' {
            if (`$env:MANUS_API_KEY) {
                `$result = Invoke-ManusText -Prompt `$Prompt
                Format-AIOutput -Text `$result.Text -Title 'Investigación' -Engine `$result.Engine -Prompt `$Prompt -ElapsedMs `$result.ElapsedMs -Theme `$result.Theme
                return
            }

            if (`$env:OPENAI_API_KEY) {
                `$result = Invoke-OpenAIText -Prompt `$Prompt -Instructions 'Responde en español, con rigor y estructura.'
                Format-AIOutput -Text `$result.Text -Title 'Investigación' -Engine `$result.Engine -Prompt `$Prompt -ElapsedMs `$result.ElapsedMs -Theme `$result.Theme
                return
            }

            if (`$env:GEMINI_API_KEY -or `$env:GOOGLE_API_KEY) {
                `$result = Invoke-GeminiText -Prompt `$Prompt -System 'Responde en español, con rigor y estructura.'
                Format-AIOutput -Text `$result.Text -Title 'Investigación' -Engine `$result.Engine -Prompt `$Prompt -ElapsedMs `$result.ElapsedMs -Theme `$result.Theme
                return
            }

            `$result = Invoke-OllamaLocal -Prompt `$Prompt -Model "$($Config.LocalReasonModel)" -System 'Responde en español, con rigor y estructura.'
            Format-AIOutput -Text `$result.Text -Title 'Investigación' -Engine `$result.Engine -Prompt `$Prompt -ElapsedMs `$result.ElapsedMs -Theme `$result.Theme
            return
        }

        default {
            if (`$Prompt.Length -lt 1500) {
                `$result = Invoke-OllamaLocal -Prompt `$Prompt -Model "$($Config.LocalChatModel)" -System 'Responde en español, claro y directo.'
                Format-AIOutput -Text `$result.Text -Title 'Chat' -Engine `$result.Engine -Prompt `$Prompt -ElapsedMs `$result.ElapsedMs -Theme `$result.Theme
                return
            }

            if (`$env:GEMINI_API_KEY -or `$env:GOOGLE_API_KEY) {
                `$result = Invoke-GeminiText -Prompt `$Prompt -System 'Responde en español, claro y directo.'
                Format-AIOutput -Text `$result.Text -Title 'Chat' -Engine `$result.Engine -Prompt `$Prompt -ElapsedMs `$result.ElapsedMs -Theme `$result.Theme
                return
            }

            if (`$env:OPENAI_API_KEY) {
                `$result = Invoke-OpenAIText -Prompt `$Prompt -Instructions 'Responde en español, claro y directo.'
                Format-AIOutput -Text `$result.Text -Title 'Chat' -Engine `$result.Engine -Prompt `$Prompt -ElapsedMs `$result.ElapsedMs -Theme `$result.Theme
                return
            }

            `$result = Invoke-OllamaLocal -Prompt `$Prompt -Model "$($Config.LocalChatModel)" -System 'Responde en español, claro y directo.'
            Format-AIOutput -Text `$result.Text -Title 'Chat' -Engine `$result.Engine -Prompt `$Prompt -ElapsedMs `$result.ElapsedMs -Theme `$result.Theme
            return
        }
    }
}

function Clear-AIContext {
    `$global:OllamaChatContext = `$null
    `$global:OllamaMessages = @()
    Write-Host "`n[OK] Contexto local (Ollama) eliminado. La próxima conversación empezará de cero.`n" -ForegroundColor Green
}

function ai-help {
    Write-Host "`n=================================================" -ForegroundColor Cyan
    Write-Host " 🤖 AYUDA DE AI STACK (Comandos Disponibles) " -ForegroundColor Cyan
    Write-Host "=================================================`n" -ForegroundColor Cyan

    Write-Host "COMANDOS LOCALES (Ollama):" -ForegroundColor Yellow
    Write-Host "  ai-local    " -NoNewline -ForegroundColor Green; Write-Host "Chat con modelo de razonamiento profundo (ej. DeepSeek-R1)."
    Write-Host "  ai-chat     " -NoNewline -ForegroundColor Green; Write-Host "Chat general rápido y directo (ej. Llama 3)."
    Write-Host "  ai-code     " -NoNewline -ForegroundColor Green; Write-Host "Chat especializado en programación (ej. Qwen)."
    
    Write-Host "`nCOMANDOS EN LA NUBE:" -ForegroundColor Yellow
    Write-Host "  ai-openai   " -NoNewline -ForegroundColor Green; Write-Host "Chat usando la API de OpenAI (ChatGPT)."
    Write-Host "  ai-gemini   " -NoNewline -ForegroundColor Green; Write-Host "Chat usando la API de Google Gemini."
    Write-Host "  ai-manus    " -NoNewline -ForegroundColor Green; Write-Host "Consultas al agente autónomo Manus."

    Write-Host "`nENRUTAMIENTO INTELIGENTE:" -ForegroundColor Yellow
    Write-Host "  ai-router   " -NoNewline -ForegroundColor Green; Write-Host "Delega la petición al mejor modelo disponible. Uso: ai-router -Task reason|code|chat|research -Prompt '...'"

    Write-Host "`nGESTIÓN:" -ForegroundColor Yellow
    Write-Host "  clear-ai    " -NoNewline -ForegroundColor Green; Write-Host "Borra la memoria de la conversación actual (Ollama)."
    Write-Host "  ai-help     " -NoNewline -ForegroundColor Green; Write-Host "Muestra esta pantalla de ayuda."

    Write-Host "`n=================================================" -ForegroundColor Cyan
    Write-Host " 💡 EJEMPLOS DE USO " -ForegroundColor Cyan
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host " Puedes iniciar un chat cautivo pasando tu primer mensaje:"
    Write-Host "    ai-local `"¿Cuáles son las leyes de la termodinámica?`"" -ForegroundColor DarkGray
    Write-Host "    ai-code `"Escribe un script de PowerShell para borrar temporales`"" -ForegroundColor DarkGray
    Write-Host "    ai-openai `"Traduce al francés este texto...`"" -ForegroundColor DarkGray

    Write-Host "`n O puedes lanzar el comando vacío para entrar directamente al chat:"
    Write-Host "    ai-chat" -ForegroundColor DarkGray
    
    Write-Host "`n Recuerda que cualquier comando (ai-local, ai-openai...) te mete en un modo chat interactivo"
    Write-Host " donde el contexto se mantiene de forma natural."
    Write-Host " Para salir de un chat y volver a la consola normal, escribe " -NoNewline; Write-Host "salir" -ForegroundColor Red -NoNewline; Write-Host ", " -NoNewline; Write-Host "quit" -ForegroundColor Red -NoNewline; Write-Host " o " -NoNewline; Write-Host "bye" -ForegroundColor Red; Write-Host "."
    Write-Host ""
}

Set-Alias air ai-router
Set-Alias clear-ai Clear-AIContext
# <<< AI STACK END <<<
"@
}

function Update-PowerShellProfile {
    $profilePath = $PROFILE.CurrentUserAllHosts
    $profileDir = Split-Path -Path $profilePath -Parent

    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }

    if (-not (Test-Path $profilePath)) {
        New-Item -ItemType File -Path $profilePath -Force | Out-Null
    }

    $content = Get-Content -Path $profilePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) { $content = '' }

    $startMarker = '# >>> AI STACK START >>>'
    $endMarker   = '# <<< AI STACK END <<<'
    $block       = Build-ProfileBlock

    if ($content -match [regex]::Escape($startMarker) -and $content -match [regex]::Escape($endMarker)) {
        $pattern = '(?s)# >>> AI STACK START >>>.*?# <<< AI STACK END <<<'
        $newContent = [regex]::Replace(
            $content,
            $pattern,
            [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $block }
        )
        Set-Content -Path $profilePath -Value $newContent -Encoding UTF8
        Write-Ok "Bloque AI STACK actualizado en el perfil: $profilePath"
    }
    else {
        Add-Content -Path $profilePath -Value "`r`n$block`r`n"
        Write-Ok "Bloque AI STACK añadido al perfil: $profilePath"
    }
}

function Test-AIEndpoints {
    Write-Host ''
    Write-Info 'Resumen de estado:'
    Write-Host ("- Ollama local    : " + ($(if (Test-OllamaResponsive) { 'OK' } else { 'NO RESPONDE' })))
    Write-Host ("- OPENAI_API_KEY  : " + ($(if ($env:OPENAI_API_KEY) { 'CONFIGURADA' } else { 'NO' })))
    Write-Host ("- GEMINI_API_KEY  : " + ($(if ($env:GEMINI_API_KEY) { 'CONFIGURADA' } else { 'NO' })))
    Write-Host ("- GOOGLE_API_KEY  : " + ($(if ($env:GOOGLE_API_KEY) { 'CONFIGURADA' } else { 'NO' })))
    Write-Host ("- MANUS_API_KEY   : " + ($(if ($env:MANUS_API_KEY) { 'CONFIGURADA' } else { 'NO' })))
    Write-Host ''
    Write-Host 'Comandos disponibles tras reabrir PowerShell:'
    Write-Host '  ai-local    <prompt>'
    Write-Host '  ai-code     <prompt>'
    Write-Host '  ai-chat     <prompt>'
    Write-Host '  ai-openai   <prompt>'
    Write-Host '  ai-gemini   <prompt>'
    Write-Host '  ai-manus    <prompt>'
    Write-Host '  ai-router   -Task reason|code|chat|research -Prompt "<texto>"'
    Write-Host '  clear-ai    (Limpia el contexto para olvidar la charla local anterior)'
    Write-Host '  ai-help     (Muestra un panel con explicaciones y ejemplos)'
    Write-Host ''
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------
try {
    Install-Ollama
    Set-OllamaTuning
    Start-Ollama

    Initialize-CloudApiKeys

    if (-not $SkipModelPull) {
        if (Test-OllamaResponsive) {
            $hw = Get-HardwareProfile
            $recs = Get-RecommendedModels -HardwareProfile $hw
            
            Write-Host ""
            Write-Ok "Modelos recomendados seleccionados:"
            Write-Host "  - Razonamiento: $($recs.LocalReasonModel)" -ForegroundColor Cyan
            Write-Host "  - Código      : $($recs.LocalCodeModel)" -ForegroundColor Cyan
            Write-Host "  - Chat        : $($recs.LocalChatModel)" -ForegroundColor Cyan
            Write-Host "  - Visión      : $($recs.LocalVisionModel)" -ForegroundColor Cyan
            Write-Host ""
            
            $Config.LocalReasonModel = $recs.LocalReasonModel
            $Config.LocalCodeModel   = $recs.LocalCodeModel
            $Config.LocalChatModel   = $recs.LocalChatModel
            $Config.LocalVisionModel = $recs.LocalVisionModel

            Install-OllamaModel -Model $Config.LocalReasonModel
            Install-OllamaModel -Model $Config.LocalCodeModel
            Install-OllamaModel -Model $Config.LocalChatModel
            Install-OllamaModel -Model $Config.LocalVisionModel
        }
        else {
            Write-Warn2 'Omito pull de modelos porque Ollama no responde aún.'
        }
    }
    else {
        Write-Warn2 'SkipModelPull activo: no descargo modelos.'
    }

    if (-not $SkipProfileUpdate) {
        Update-PowerShellProfile
    }
    else {
        Write-Warn2 'SkipProfileUpdate activo: no toco tu perfil.'
    }

    Test-AIEndpoints

    Write-Host 'Pruebas rápidas:' -ForegroundColor Magenta
    Write-Host '  ai-chat "Explícame qué diferencia hay entre kW y kWh"' -ForegroundColor Gray
    Write-Host '  ai-code "Hazme una función PowerShell que liste ficheros grandes >500MB"' -ForegroundColor Gray
    Write-Host '  ai-openai "hola, dime qué modelo eres"' -ForegroundColor Gray
    Write-Host '  ai-gemini "hola, dime qué modelo eres"' -ForegroundColor Gray
    Write-Host ''
    Write-Ok 'Hecho. Cierra y abre PowerShell para cargar las funciones del perfil.'
}
catch {
    Write-Err2 (Get-ExceptionSummary -ErrorRecord $_)
    throw
}

