<#
.SYNOPSIS
    Ejecuta comandos o programas con privilegios de administrador (estilo 'sudo').

.DESCRIPTION
    Esta función permite ejecutar comandos o scripts elevando privilegios si el usuario
    no está en una sesión de PowerShell como administrador. Si ya tiene privilegios,
    ejecuta directamente sin reelevar.

    Compatible con pwsh (PowerShell 7+) y con Windows PowerShell clásico (v5).

.EXAMPLE
    sudo "Set-ExecutionPolicy RemoteSigned -Force"

.EXAMPLE
    Invoke-Sudo -FilePath "notepad.exe"

.EXAMPLE
    Invoke-Sudo -FilePath "C:\Scripts\MisTareas.ps1" -ArgumentList "-Verbose" -Wait

.EXAMPLE
    sudo -UseWindowsPowerShell "Get-Service | Out-GridView"

.NOTES
    Autor: PowerShell Forge (versión 1.0.0)
    Fecha: 2025-10-27
#>

function Test-IsAdmin {
    <#
    .SYNOPSIS
        Comprueba si el usuario actual tiene privilegios de administrador.
    #>
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = [Security.Principal.WindowsPrincipal]::new($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Sudo {
    <#
    .SYNOPSIS
        Ejecuta un comando o archivo como administrador, similar a 'sudo' en Linux.

    .PARAMETER CommandLine
        Comando inline que se ejecutará con elevación.

    .PARAMETER FilePath
        Ruta a un ejecutable o script que se ejecutará con privilegios de administrador.

    .PARAMETER ArgumentList
        Argumentos para pasar al archivo o script.

    .PARAMETER Wait
        Espera a que el proceso elevado finalice antes de continuar.

    .PARAMETER PassThru
        Devuelve el objeto del proceso creado.

    .PARAMETER UseWindowsPowerShell
        Usa Windows PowerShell (v5) en lugar de PowerShell 7+ (pwsh).

    .EXAMPLE
        sudo "Get-Process"
    #>
    [CmdletBinding(DefaultParameterSetName='Inline')]
    param(
        [Parameter(ParameterSetName='Inline', Position=0, ValueFromRemainingArguments=$true)]
        [string[]]$CommandLine,

        [Parameter(ParameterSetName='File', Mandatory)]
        [string]$FilePath,
        [Parameter(ParameterSetName='File')]
        [string[]]$ArgumentList,

        [switch]$Wait,
        [switch]$PassThru,
        [switch]$UseWindowsPowerShell
    )

    $isAdmin = Test-IsAdmin

    if ($isAdmin) {
        # Ya somos admin → ejecuta directamente
        if ($PSCmdlet.ParameterSetName -eq 'File') {
            $psi = [System.Diagnostics.ProcessStartInfo]::new()
            $psi.FileName = $FilePath
            if ($ArgumentList) { $psi.Arguments = [string]::Join(' ', $ArgumentList) }
            $proc = [System.Diagnostics.Process]::Start($psi)
            if ($Wait) { $proc.WaitForExit() }
            if ($PassThru) { return $proc }
            return
        } else {
            if ($CommandLine -and $CommandLine.Count -gt 0) {
                $cmd = $CommandLine -join ' '
                Invoke-Expression -Command $cmd
            }
            return
        }
    }

    # No somos admin → elevar
    $shellPath = if ($UseWindowsPowerShell) {
        Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    } else {
        (Get-Process -Id $PID).Path
    }

    # Monta el comando interno
    if ($PSCmdlet.ParameterSetName -eq 'File') {
        $escapedFile = ('"{0}"' -f ($FilePath -replace '"','`"'))
        if ($ArgumentList) {
            $escapedArgs = $ArgumentList | ForEach-Object { '"{0}"' -f ($_ -replace '"','`"') }
            $inner = "& $escapedFile $([string]::Join(' ', $escapedArgs))"
        } else {
            $inner = "& $escapedFile"
        }
    } else {
        $inner = ($CommandLine -join ' ')
    }

    # Codifica en Base64 para evitar errores de comillas/acentos
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($inner)
    $enc   = [Convert]::ToBase64String($bytes)
    $args  = @('-NoProfile','-EncodedCommand', $enc)

    $proc = Start-Process -FilePath $shellPath -Verb RunAs -ArgumentList $args -PassThru
    if ($Wait) { $proc.WaitForExit() }
    if ($PassThru) { return $proc }
}

# Alias de conveniencia
Set-Alias -Name sudo -Value Invoke-Sudo
Export-ModuleMember -Function Invoke-Sudo,Test-IsAdmin -Alias sudo 2>$null
