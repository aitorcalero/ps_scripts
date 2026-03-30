# ====================================================================================
# OpenAI PS Terminal Booster — versión Cloud
# ====================================================================================

if (Get-Variable -Name "OpenAI_PS_Initialized" -Scope Global -ErrorAction SilentlyContinue) { return }
$Global:OpenAI_PS_Initialized = $true
$Global:OpenAI_PS_Memory = @() # Array para almacenar el contexto de la conversación

# Forzar UTF-8 para evitar caracteres "raros" en consola
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new() } catch {}

# --- Config por defecto -------------------------------------------------------------
$Global:OpenAI_PS_Config = [ordered]@{
    DefaultModel    = 'gpt-4o'      # Modelo por defecto (gpt-4o, gpt-4o-mini, gpt-4-turbo)
    ApiKeyEnv       = 'OPENAI_API_KEY'
    MaxMemoryItems  = 10            # Número máximo de mensajes a recordar para no gastar muchos tokens
    CopyToClipboard = $true
    DefaultRun      = $false        # Por defecto NO ejecuta (solo muestra), a menos que uses -Run
    SafeMode        = $true         # Chequeos básicos de seguridad antes de ejecutar
    SystemPrompt    = @"
Eres un experto desarrollador de PowerShell de nivel 10. Tu tarea es proporcionar EXCLUSIVAMENTE código PowerShell funcional y robusto dentro de un único bloque de triple comilla (```powershell ... ```), sin explicaciones adicionales.

REGLAS ESTRICTAS:
1. Usa cmdlets nativos siempre que sea posible. Si necesitas utilizar objetos COM, clases .NET o llamadas a la API de Windows, asegúrate de que sean correctas y estén soportadas.
2. NUNCA asumas la existencia de providers de PowerShell que no vienen por defecto (por ejemplo, NO uses paths como 'Recycle:\' porque no existen nativamente).
3. Todo tu código debe ser robusto e incluir manejo de errores (try/catch). Sin embargo, si capturas un error y decides informarlo, usa `Write-Warning` o `Write-Host` en lugar de `Write-Error` o `throw` para no interrumpir el host de ejecución principal, a menos que sea críticamente inmanejable.
4. Si necesitas instalar submódulos, hazlo de forma idempotente.
5. Evita comandos destructivos (Remove-Item, Stop-Process, etc.) a menos que el usuario lo pida explícitamente, y de ser así, añade un comentario de advertencia.
"@
}

# --- Helpers ------------------------------------------------------------------------

function Ensure-OpenAIApiKey {
    # Intenta obtener la API key desde las variables de entorno
    $key = [Environment]::GetEnvironmentVariable($Global:OpenAI_PS_Config.ApiKeyEnv, 'Process')
    if (-not $key) { $key = [Environment]::GetEnvironmentVariable($Global:OpenAI_PS_Config.ApiKeyEnv, 'User') }
    if (-not $key) { $key = [Environment]::GetEnvironmentVariable($Global:OpenAI_PS_Config.ApiKeyEnv, 'Machine') }

    if (-not $key) {
        Write-Host "⚠ No se ha encontrado la clave API de OpenAI en la variable de entorno $($Global:OpenAI_PS_Config.ApiKeyEnv)." -ForegroundColor Yellow
        $key = Read-Host "Por favor, introduce tu OpenAI API Key (se guardará de forma persistente en el entorno del Usuario)"
        if ([string]::IsNullOrWhiteSpace($key)) {
            throw "Se requiere una API Key de OpenAI para continuar."
        }
        # Guardar para futuros usos y para la sesión actual
        [Environment]::SetEnvironmentVariable($Global:OpenAI_PS_Config.ApiKeyEnv, $key, 'User')
        [Environment]::SetEnvironmentVariable($Global:OpenAI_PS_Config.ApiKeyEnv, $key, 'Process')
    }
    return $key
}

function Invoke-OpenAIGenerate {
    param(
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$Prompt,
        [string]$System = $Global:OpenAI_PS_Config.SystemPrompt
    )
    $ApiKey = Ensure-OpenAIApiKey

    $headers = @{
        "Authorization" = "Bearer $ApiKey"
        "Content-Type"  = "application/json"
    }

    # Determinar si es un modelo tipo "o1" u "o3" (razonamiento)
    $isReasoningModel = $Model -match "^(o1|o3)"

    # El rol de sistema para los modelos de razonamiento (ej: o3-mini) suele ser 'developer' en lugar de 'system'
    $systemRole = if ($isReasoningModel) { "developer" } else { "system" }

    # Construir el array de mensajes con el contexto histórico
    $messages = @(
        @{ role = $systemRole; content = $System }
    )
    
    # Añadir memoria previa
    if ($Global:OpenAI_PS_Memory.Count -gt 0) {
        $messages += $Global:OpenAI_PS_Memory
    }
    
    # Añadir el mensaje actual
    $userMessage = @{ role = "user"; content = $Prompt }
    $messages += $userMessage

    # OpenAI Chat API requiere 'messages'
    $bodyObj = @{
        model    = $Model
        messages = $messages
    }
    
    # Los modelos o1 y o3 no soportan `temperature`
    if (-not $isReasoningModel) {
        $bodyObj.temperature = 0.2
    }

    $bodyJson = $bodyObj | ConvertTo-Json -Depth 5 -Compress

    $uri = "https://api.openai.com/v1/chat/completions"

    try {
        Write-Host "☁️  Consultando OpenAI ($Model) con $(if($Global:OpenAI_PS_Memory.Count -gt 0){"contexto de $($Global:OpenAI_PS_Memory.Count) mnsjs anteriores "}else{"sin contexto previo"})..." -ForegroundColor Cyan
        $result = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $bodyJson -ErrorAction Stop
        if ($result.choices -and $result.choices.Count -gt 0) {
            $assistantResponse = $result.choices[0].message.content
            
            # Guardar en memoria para el próximo turno
            $Global:OpenAI_PS_Memory += $userMessage
            $Global:OpenAI_PS_Memory += @{ role = "assistant"; content = $assistantResponse }
            
            # Limpiar memoria si excede el límite (mantener siempre pares de pregunta/respuesta)
            if ($Global:OpenAI_PS_Memory.Count -gt ($Global:OpenAI_PS_Config.MaxMemoryItems * 2)) {
                $excess = $Global:OpenAI_PS_Memory.Count - ($Global:OpenAI_PS_Config.MaxMemoryItems * 2)
                $Global:OpenAI_PS_Memory = $Global:OpenAI_PS_Memory[$excess..($Global:OpenAI_PS_Memory.Count - 1)]
            }

            return $assistantResponse
        }
        else {
            throw "Respuesta inesperada de la API: $($result | ConvertTo-Json -Depth 3)"
        }
    }
    catch {
        Write-Error "Error al conectar con OpenAI API: $($_.Exception.Message)"
        if ($_.ErrorDetails) {
            Write-Error "Detalles: $($_.ErrorDetails.Message)"
        }
        throw
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
    if (-not $Global:OpenAI_PS_Config.SafeMode) { return $true }

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

function Invoke-OpenAIPowerShell {
    <#
  .SYNOPSIS
    Genera código PowerShell desde lenguaje natural usando el API en la nube de OpenAI (gpt-4o, etc.), y opcionalmente lo ejecuta.

  .PARAMETER Prompt
    Descripción en lenguaje natural de lo que necesitas.

  .PARAMETER InputObject
    Datos de entrada a través del pipeline.

  .PARAMETER Model
    Nombre del modelo de OpenAI (ej. 'gpt-4o', 'gpt-4o-mini'). Por defecto 'gpt-4o'.

  .PARAMETER Run
    Ejecuta el código generado tras mostrarlo (pasa los chequeos de seguridad básicos).

  .PARAMETER ClearMemory
    Borra la memoria temporal de la conversación actual. Útil si quieres empezar con contexto limpio.

  .EXAMPLE
    ai-cloud "Lista los procesos que consumen más de 500MB de RAM"

  .EXAMPLE
    Get-Process | ai-cloud "Encuentra el proceso que más memoria consume de esta lista y muestra su nombre"
  
  .EXAMPLE
    ai-cloud -Run "Crea un archivo de prueba en mi escritorio llamado 'dummy.txt'"

  .EXAMPLE
    ai-cloud -ClearMemory "Escribe un script de hola mundo"
  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [string]$Prompt = "",
    
        [Parameter(ValueFromPipeline = $true)]
        [psobject[]]$InputObject,

        [string]$Model = $Global:OpenAI_PS_Config.DefaultModel,
    
        [switch]$Run,

        [switch]$ClearMemory
    )

    BEGIN {
        $pipelineData = [System.Collections.Generic.List[string]]::new()
    }

    PROCESS {
        if ($InputObject) {
            foreach ($item in $InputObject) {
                if ($item -is [string]) {
                    $pipelineData.Add($item)
                }
                else {
                    # Convert object to string representation for context
                    $pipelineData.Add(($item | Out-String).Trim())
                }
            }
        }
    }

    END {
        if ($ClearMemory.IsPresent) {
            $Global:OpenAI_PS_Memory = @()
            Write-Host "🧹 Memoria de sesión borrada." -ForegroundColor DarkCyan
            if ([string]::IsNullOrWhiteSpace($Prompt) -and $pipelineData.Count -eq 0) {
                return # Si solo borró la memoria y no dio prompt, terminamos
            }
        }

        if ([string]::IsNullOrWhiteSpace($Prompt) -and $pipelineData.Count -eq 0) {
            Write-Error "Se introdujo un comando AI pero falta el Prompt. Ejemplo: ai-cloud 'haz x'"
            return
        }
        # Combinar el prompt con la entrada del pipeline (si existe)
        $finalPrompt = $Prompt
        if ($pipelineData.Count -gt 0) {
            $pipelineContext = $pipelineData -join "`n"
            $finalPrompt = "$Prompt`n`n--- DATOS DE ENTRADA ---`n$pipelineContext"
        }

        Write-Host "🤖 Modelo Cloud: $Model" -ForegroundColor Green
        Write-Host "📝 Prompt: $Prompt" -ForegroundColor Green
        if ($pipelineData.Count -gt 0) {
            $dataPreview = if ($pipelineContext.Length -gt 100) { $pipelineContext.Substring(0, 100) + "..." } else { $pipelineContext }
            Write-Host "📥 Input detectado: $dataPreview" -ForegroundColor DarkGray
        }

        # Llamada al LLM
        try {
            $raw = Invoke-OpenAIGenerate -Model $Model -Prompt $finalPrompt
        }
        catch {
            return
        }

        $code = Extract-PowerShellCode -Text $raw

        if ([string]::IsNullOrWhiteSpace($code)) {
            Write-Error "El modelo no devolvió código."
            return
        }

        Write-Host "================= CÓDIGO GENERADO (solo lectura) =================" -ForegroundColor Yellow
        Write-Host $code
        Write-Host "===================================================================" -ForegroundColor Yellow

        if ($Global:OpenAI_PS_Config.CopyToClipboard -and (Get-Command Set-Clipboard -ErrorAction SilentlyContinue)) {
            $code | Set-Clipboard
            Write-Host "📋 Copiado al portapapeles." -ForegroundColor Cyan
        }

        # Ejecutar con Auto-Recuperación (Self-Healing)
        $shouldRun = $Run.IsPresent -or $Global:OpenAI_PS_Config.DefaultRun
        if ($shouldRun) {
            $maxRetries = 2
            $attempt = 1
            $success = $false
            $currentCode = $code

            while ($attempt -le $maxRetries -and -not $success) {
                if (-not (Test-CodeSafety -Code $currentCode)) {
                    Write-Error "Ejecución cancelada por reglas de seguridad. Revisa el código."
                    return
                }

                $attemptLabel = if ($attempt -gt 1) { " (Auto-Reparación $attempt)" } else { "" }
                Write-Host "▶️  Ejecutando código$attemptLabel..." -ForegroundColor Cyan
                
                $initialErrorCount = $Error.Count
                $errMsg = $null

                try {
                    $scriptBlock = [ScriptBlock]::Create($currentCode)
                    # Aislar el ErrorActionPreference solo para este bloque pero no forzar 'Stop' en todo
                    # para que Write-Error del código generado no se convierta obligatoriamente en un terminating error
                    & $scriptBlock
                    # Si termina el script sin hacer throw, asumiremos éxito
                    $success = $true
                }
                catch {
                    $errMsg = $_.Exception.Message
                }

                # Si el bloque falló o generó un 'Write-Error' que abortó la operación,
                # procesamos el self-healing. Si simplemente hubo un error silencioso no capturado,
                # o usamos Write-Host, $success seguirá siendo True y el errMsg nulo.
                if (-not $success -and -not $errMsg -and $Error.Count -gt $initialErrorCount) {
                    $errMsg = $Error[0].Exception.Message
                }

                if ($errMsg) {
                    Write-Error "❌ Fallo al ejecutar el script generado: $errMsg"
                    
                    if ($attempt -lt $maxRetries) {
                        Write-Host "🔄 Intentando corregir el error automáticamente..." -ForegroundColor DarkYellow
                        
                        $fixPrompt = @"
El script que has generado falló al ejecutarse.

Error: $errMsg

Analiza el error y devuelve SOLO el nuevo código corregido.
Si el usuario solicitó un error intencionado (como dividir por cero o probar excepciones), simplemente genera código que demuestre el error y lo capture limpiamente con un bloque try/catch y lo escriba por pantalla usando Write-Host, NUNCA propagues el error usando Write-Error o throw.
"@
                        
                        try {
                            $rawFix = Invoke-OpenAIGenerate -Model $Model -Prompt $fixPrompt
                            $currentCode = Extract-PowerShellCode -Text $rawFix
                            
                            Write-Host "================= CÓDIGO CORREGIDO ====================" -ForegroundColor Yellow
                            Write-Host $currentCode
                            Write-Host "=======================================================" -ForegroundColor Yellow
                        }
                        catch {
                            break
                        }
                    }
                    else {
                        Write-Error "Se alcanzó el límite máximo de reintentos."
                    }
                }
                else {
                    $success = $true
                }
                $attempt++
            }
        }
        else {
            Write-Host "ℹ️  No se ejecuta automáticamente. Usa -Run para ejecutar (ej: ai-cloud -Run `"...`")." -ForegroundColor DarkCyan
        }
    }
}

# --- Aliases de uso rápido -----------------------------------------------------------
Set-Alias -Name ai-cloud -Value Invoke-OpenAIPowerShell -Scope Global

# Exponer la función 'aic!' al ámbito global para que no requiera dot-sourcing
function Global:aic! { 
    param([Parameter(ValueFromRemainingArguments = $true)]$Args) 
    Invoke-OpenAIPowerShell -Prompt ($Args -join ' ') -Run 
}

# --- Preparación / Verificación inicial (opcional) -----------------------------------
try {
    # Verificamos si la key está (sin forzar el prompt inicial al cargar el script)
    $key = [Environment]::GetEnvironmentVariable($Global:OpenAI_PS_Config.ApiKeyEnv, 'Process')
    if (-not $key) { $key = [Environment]::GetEnvironmentVariable($Global:OpenAI_PS_Config.ApiKeyEnv, 'User') }
  
    if ($key) {
        Write-Host "✅ Entorno de la nube listo (API Key detectada)." -ForegroundColor Green
    }
    else {
        Write-Host "ℹ️  Entorno de la nube listo. Se solicitará la API Key en el primer comando." -ForegroundColor DarkCyan
    }
    Write-Host "   Prueba:  ai-cloud 'Crea un script que comprima los archivos del escritorio más antiguos a 30 días'" -ForegroundColor Green
    Write-Host "   Usar y ejecutar: ai-cloud -Run 'Muestra la fecha actual'" -ForegroundColor Green
}
catch {
    Write-Warning $_
}
