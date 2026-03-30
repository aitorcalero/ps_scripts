# ====================================================================================
# AI Cloud PowerShell (OpenAI Responses API)
# Usage:
#   . .\AI_PowerShell_Cloud.ps1
#   ai-cloud "create a script that lists stopped services and exports CSV"
#   ai-cloud -Run "same, and save output to C:\Temp\services.csv"
# ====================================================================================

if ((Test-Path variable:Global:AI_Cloud_PS_Initialized) -and $Global:AI_Cloud_PS_Initialized) { return }
$Global:AI_Cloud_PS_Initialized = $true

try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new() } catch {}

$Global:AI_Cloud_PS_Config = [ordered]@{
  ApiBase         = "https://api.openai.com/v1"
  DefaultModel    = "gpt-5-nano"
  FallbackModel   = "gpt-4.1-mini"
  CopyToClipboard = $true
  DefaultRun      = $false
  SafeMode        = $true
  RequestTimeout  = 180
  SystemPrompt    = @"
You generate PowerShell code from user instructions.
Return only one fenced block: ```powershell ... ```
No extra prose outside that block.
Prefer native cmdlets, idempotent behavior, and safe defaults.
Avoid destructive operations unless explicitly requested.
"@
}

function Get-OpenAIApiKey {
  $apiKey = $env:OPENAI_API_KEY
  if ([string]::IsNullOrWhiteSpace($apiKey)) {
    throw "OPENAI_API_KEY is not set. Define it before using ai-cloud."
  }
  return $apiKey
}

function New-OpenAIHeaders {
  $headers = @{
    Authorization = "Bearer $(Get-OpenAIApiKey)"
    "Content-Type" = "application/json"
  }

  if (-not [string]::IsNullOrWhiteSpace($env:OPENAI_ORG_ID)) {
    $headers["OpenAI-Organization"] = $env:OPENAI_ORG_ID
  }

  if (-not [string]::IsNullOrWhiteSpace($env:OPENAI_PROJECT_ID)) {
    $headers["OpenAI-Project"] = $env:OPENAI_PROJECT_ID
  }

  return $headers
}

function Invoke-OpenAIResponses {
  param(
    [Parameter(Mandatory)][string]$Model,
    [Parameter(Mandatory)][string]$Prompt,
    [Parameter(Mandatory)][string]$Instructions
  )

  $headers = New-OpenAIHeaders
  $uri = "$($Global:AI_Cloud_PS_Config.ApiBase.TrimEnd('/'))/responses"
  $body = @{
    model = $Model
    instructions = $Instructions
    input = $Prompt
  } | ConvertTo-Json -Depth 8

  try {
    return Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body -TimeoutSec $Global:AI_Cloud_PS_Config.RequestTimeout
  } catch {
    $status = $null
    $details = $_.Exception.Message
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
      $status = [int]$_.Exception.Response.StatusCode
    }
    if ($status) {
      throw "OpenAI API error ($status): $details"
    }
    throw "OpenAI API request failed: $details"
  }
}

function Get-OpenAIResponseText {
  param([Parameter(Mandatory)]$Response)

  if ($Response.PSObject.Properties.Name -contains "output_text") {
    $t = [string]$Response.output_text
    if (-not [string]::IsNullOrWhiteSpace($t)) { return $t }
  }

  $parts = [System.Collections.Generic.List[string]]::new()

  if ($Response.PSObject.Properties.Name -contains "output") {
    foreach ($item in @($Response.output)) {
      if ($null -eq $item) { continue }

      if ($item.PSObject.Properties.Name -contains "content") {
        foreach ($content in @($item.content)) {
          if ($null -eq $content) { continue }

          if ($content.PSObject.Properties.Name -contains "text") {
            $text = [string]$content.text
            if (-not [string]::IsNullOrWhiteSpace($text)) {
              $parts.Add($text) | Out-Null
            }
          }
        }
      }
    }
  }

  return ($parts -join "`n").Trim()
}

function Extract-PowerShellCode {
  param([Parameter(Mandatory)][string]$Text)

  $regexes = @(
    '(?s)```powershell\s+(.*?)```',
    '(?s)```pwsh\s+(.*?)```',
    '(?s)```ps1\s+(.*?)```',
    '(?s)```\s*(.*?)```'
  )

  foreach ($rx in $regexes) {
    $m = [regex]::Match($Text, $rx)
    if ($m.Success -and $m.Groups.Count -gt 1) {
      return $m.Groups[1].Value.Trim()
    }
  }

  return $Text.Trim()
}

function Test-CodeSafety {
  param([Parameter(Mandatory)][string]$Code)

  if (-not $Global:AI_Cloud_PS_Config.SafeMode) { return $true }

  $dangerPatterns = @(
    "(?i)\bRemove-Item\b.+\s-Recurse\b.+\s-Force\b",
    "(?i)\bFormat-Volume\b",
    "(?i)\bRemove-Computer\b",
    "(?i)\bClear-Disk\b",
    "(?i)\bSet-ExecutionPolicy\s+Unrestricted\b",
    "(?i)\bInvoke-Expression\b",
    "(?i)\biex\b"
  )

  foreach ($pattern in $dangerPatterns) {
    if ([regex]::IsMatch($Code, $pattern)) {
      Write-Warning "Blocked by safety pattern: $pattern"
      return $false
    }
  }

  return $true
}

function Invoke-AICloudPowerShell {
  <#
  .SYNOPSIS
    Generate PowerShell code from natural language using OpenAI cloud models.

  .PARAMETER Prompt
    Natural language instructions describing what the script should do.

  .PARAMETER Model
    OpenAI model id. If omitted, uses DefaultModel and then FallbackModel.

  .PARAMETER Run
    Execute generated code after showing it.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Prompt,
    [string]$Model,
    [switch]$Run
  )

  $candidates = @()
  if ([string]::IsNullOrWhiteSpace($Model)) {
    $candidates = @(
      $Global:AI_Cloud_PS_Config.DefaultModel,
      $Global:AI_Cloud_PS_Config.FallbackModel
    ) | Select-Object -Unique
  } else {
    $candidates = @($Model)
  }

  $response = $null
  $selectedModel = $null
  $lastError = $null

  foreach ($candidate in $candidates) {
    try {
      $response = Invoke-OpenAIResponses -Model $candidate -Prompt $Prompt -Instructions $Global:AI_Cloud_PS_Config.SystemPrompt
      $selectedModel = $candidate
      break
    } catch {
      $lastError = $_
      if (-not [string]::IsNullOrWhiteSpace($Model)) { break }
    }
  }

  if ($null -eq $response) {
    throw "No response from OpenAI. $($lastError.Exception.Message)"
  }

  Write-Host "Model: $selectedModel" -ForegroundColor Green
  Write-Host "Prompt: $Prompt" -ForegroundColor Green

  $rawText = Get-OpenAIResponseText -Response $response
  if ([string]::IsNullOrWhiteSpace($rawText)) {
    throw "The model response did not include text content."
  }

  $code = Extract-PowerShellCode -Text $rawText
  if ([string]::IsNullOrWhiteSpace($code)) {
    throw "The model response did not include PowerShell code."
  }

  Write-Host "================= GENERATED CODE (read-only) =================" -ForegroundColor Yellow
  Write-Host $code
  Write-Host "===============================================================" -ForegroundColor Yellow

  if ($Global:AI_Cloud_PS_Config.CopyToClipboard -and (Get-Command Set-Clipboard -ErrorAction SilentlyContinue)) {
    $code | Set-Clipboard
    Write-Host "Copied to clipboard." -ForegroundColor Cyan
  }

  $shouldRun = $Run.IsPresent -or $Global:AI_Cloud_PS_Config.DefaultRun
  if (-not $shouldRun) {
    Write-Host "Not executed. Use -Run to execute generated code." -ForegroundColor DarkCyan
    return
  }

  if (-not (Test-CodeSafety -Code $code)) {
    throw "Execution blocked by safety checks."
  }

  try {
    Write-Host "Executing generated code..." -ForegroundColor Cyan
    $scriptBlock = [ScriptBlock]::Create($code)
    & $scriptBlock
  } catch {
    throw "Generated code execution failed: $($_.Exception.Message)"
  }
}

function ai-cloud {
  [CmdletBinding()]
  param(
    [switch]$Run,
    [string]$Model,
    [Parameter(ValueFromRemainingArguments = $true, Position = 0)]
    [string[]]$Instruction
  )

  $prompt = ($Instruction -join " ").Trim()
  if ([string]::IsNullOrWhiteSpace($prompt)) {
    Write-Host 'Usage: ai-cloud "<instructions>"' -ForegroundColor Yellow
    Write-Host '       ai-cloud -Run "<instructions>"' -ForegroundColor Yellow
    return
  }

  Invoke-AICloudPowerShell -Prompt $prompt -Model $Model -Run:$Run
}


