<#
.SYNOPSIS
Detecta apps en Inicio (Run/Startup) y crea tareas programadas con retardo según prioridad.

.DESCRIPTION
Explora Run (HKCU/HKLM) y carpetas Startup (usuario/común), consulta el estado en StartupApproved
(incluyendo opción para ver también los deshabilitados), asigna una prioridad heurística y registra
tareas "At log on" con delays escalonados. Puede deshabilitar el inicio original para evitar duplicados,
y re-habilitarlo al eliminar las tareas.

.PARAMETER Register
Crea/actualiza las tareas escalonadas para los elementos detectados.

.PARAMETER Test
Lanza ahora las tareas creadas (ignora el retardo de arranque).

.PARAMETER Remove
Elimina todas las tareas creadadas por este script y (opcional) re-habilita los inicios originales.

.PARAMETER List
Muestra los elementos detectados con su prioridad y el delay propuesto.

.PARAMETER IncludeDisabled
Incluye también elementos deshabilitados en StartupApproved al listar/registrar.

.PARAMETER DisableOriginals
Al registrar, marca como Deshabilitado el inicio original (StartupApproved). Por defecto: $true.

.PARAMETER ReenableOriginalsOnRemove
Al eliminar tareas, re-habilita los elementos originales. Por defecto: $true.

.PARAMETER Prefix
Prefijo para nombres de tarea. Por defecto: 'StaggeredAuto'.

.PARAMETER BaseDelays
Retardos base por prioridad (segundos) en orden: Crítico, Alto, Medio, Bajo. Por defecto: 0,15,45,90.

.PARAMETER StepWithinBucket
Paso incremental (segundos) dentro de una misma prioridad. Por defecto: 15.

.NOTES
• Ejecutar en PowerShell 7+ como Administrador para registrar tareas con RunLevel Highest.
• Probado en Windows 11. Requiere módulo ScheduledTasks (incluido en Windows).
#>

[CmdletBinding(DefaultParameterSetName='Register')]
param(
    [Parameter(ParameterSetName='Register')]
    [switch]$Register,

    [Parameter(ParameterSetName='Test')]
    [switch]$Test,

    [Parameter(ParameterSetName='Remove')]
    [switch]$Remove,

    [Parameter(ParameterSetName='List')]
    [switch]$List,

    # Mostrar/usar también elementos deshabilitados en StartupApproved
    [Parameter(ParameterSetName='Register')]
    [Parameter(ParameterSetName='List')]
    [switch]$IncludeDisabled,

    [string]$Prefix = 'StaggeredAuto',

    [int[]]$BaseDelays = @(0,15,45,90),

    [int]$StepWithinBucket = 15,

    [bool]$DisableOriginals = $true,

    [bool]$ReenableOriginalsOnRemove = $true
)

# --- Utilidad de elevación ---
function Assert-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "Elevando a administrador..."
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = (Get-Process -Id $PID).Path
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" " + $MyInvocation.Line.Replace($MyInvocation.InvocationName,'')
        $psi.Verb = "runas"
        try { [Diagnostics.Process]::Start($psi) | Out-Null } catch { throw "No se pudo elevar a administrador. $_" }
        exit
    }
}

# --- Rutas de registro y carpetas ---
$Reg_Run_HKCU = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$Reg_Run_HKLM = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
$Reg_Run_HKLM_Wow = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'

$Reg_Approved_HKCU_Run    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
$Reg_Approved_HKCU_Run32  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'
$Reg_Approved_HKCU_Folder = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
$Reg_Approved_HKLM_Run    = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
$Reg_Approved_HKLM_Run32  = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'

$Startup_User   = [Environment]::GetFolderPath('Startup') # %APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup
$Startup_Common = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup'

# --- Helpers StartupApproved ---
function Get-StartupApprovedState {
    param(
        [string]$Hive,
        [string]$Name,
        [string]$Area
    )
    $path = switch ($Area) {
        'Run'           { if ($Hive -eq 'HKCU') { $Reg_Approved_HKCU_Run } else { $Reg_Approved_HKLM_Run } }
        'Run32'         { if ($Hive -eq 'HKCU') { $Reg_Approved_HKCU_Run32 } else { $Reg_Approved_HKLM_Run32 } }
        'StartupFolder' { $Reg_Approved_HKCU_Folder } # aprobación de carpeta solo en HKCU
        default { $null }
    }
    if (-not $path) { return $true } # si no hay ruta de aprobación, asumir habilitado
    try {
        $val = (Get-ItemProperty -Path $path -Name $Name -ErrorAction Stop).$Name
        # Byte 0x02 = Enabled, 0x03 = Disabled
        return ($val[0] -eq 2)
    } catch {
        return $true # sin entrada → habilitado
    }
}

function Set-StartupApprovedState {
    param(
        [string]$Hive,
        [string]$Name,
        [string]$Area,
        [bool]$Enabled
    )
    $path = switch ($Area) {
        'Run'           { if ($Hive -eq 'HKCU') { $Reg_Approved_HKCU_Run } else { $Reg_Approved_HKLM_Run } }
        'Run32'         { if ($Hive -eq 'HKCU') { $Reg_Approved_HKCU_Run32 } else { $Reg_Approved_HKLM_Run32 } }
        'StartupFolder' { $Reg_Approved_HKCU_Folder }
        default { $null }
    }
    if (-not $path) { return }
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    # Valor binario mínimo con primer byte como estado (2=Enabled, 3=Disabled)
    $data = if ($Enabled) { [byte[]](2,0,0,0,0,0,0,0) } else { [byte[]](3,0,0,0,0,0,0,0) }
    New-ItemProperty -Path $path -Name $Name -PropertyType Binary -Value $data -Force | Out-Null
}

# --- Otros helpers ---
function Split-CommandLine {
    param([string]$Command)
    if ([string]::IsNullOrWhiteSpace($Command)) { return @($null,$null) }
    $cmd = $Command.Trim()
    if ($cmd.StartsWith('"')) {
        $closing = $cmd.IndexOf('"',1)
        if ($closing -lt 0) { return @($cmd.Trim('"'), '') }
        $exe  = $cmd.Substring(1, $closing-1)
        $args = $cmd.Substring($closing+1).Trim()
    } else {
        $parts = $cmd.Split(' ',2,[System.StringSplitOptions]::RemoveEmptyEntries)
        $exe  = $parts[0].Trim('"')
        $args = if ($parts.Count -gt 1) { $parts[1] } else { '' }
    }
    return @($exe,$args)
}

function Resolve-Shortcut {
    param([string]$LnkPath)
    try {
        $wsh = New-Object -ComObject WScript.Shell
    } catch {
        throw "No se pudo crear WScript.Shell (COM). Si usas pwsh en MTA, ejecuta en Windows PowerShell o lanza pwsh con compatibilidad COM."
    }
    $sh  = $wsh.CreateShortcut($LnkPath)
    $target = $sh.TargetPath
    $args   = $sh.Arguments
    if (-not $target) { return $null }
    [pscustomobject]@{ Path = $target; Args = $args }
}

function Guess-Priority {
    param([string]$Name,[string]$Path,[string]$Args)
    $n = ($Name + ' ' + $Path + ' ' + $Args).ToLower()

    # 0 = Crítico: seguridad/VPN/contraseñas/MFA
    if ($n -match 'bitdefender|defender|kaspersky|eset|crowdstrike|sentinel|vpn|openvpn|wireguard|protonvpn|zerotier|tailscale|1password|keepass|lastpass|enpass|bitwarden|authy|duo|yubikey') { return 0 }

    # 1 = Alto: drivers periféricos/gráficos/hotkeys/thunderbolt
    if ($n -match 'logi|logitech|razer|wacom|intel.*tray|nvidia|amd.*radeon|audio.*realtek|steelseries|thunderbolt|ime|hotkeys') { return 1 }

    # 2 = Medio: productividad base (Outlook) + Esri + remotos + nubes
    if ($n -match 'outlook|thunderbird|anydesk|teamviewer|onedrive|dropbox|googledrive|box|mega|synology|nextcloud|arcgis|esri|pro\\bin\\arcgispro\.exe') { return 2 }

    # 3 = Bajo: comunicación pesada/ocio
    if ($n -match 'teams|slack|zoom|webex|spotify|steam|epic|discord') { return 3 }

    return 2
}

function Get-StartupItems {
    param([switch]$IncludeDisabled)

    $items = @()

    # Run HKCU/HKLM
    foreach ($entry in @(
        @{ Path=$Reg_Run_HKCU;     Hive='HKCU'; Area='Run'   }
        @{ Path=$Reg_Run_HKLM;     Hive='HKLM'; Area='Run'   }
        @{ Path=$Reg_Run_HKLM_Wow; Hive='HKLM'; Area='Run32' }
    )) {
        if (-not (Test-Path $entry.Path)) { continue }
        $props = Get-ItemProperty -Path $entry.Path
        foreach ($p in ($props.PSObject.Properties | Where-Object { $_.Name -notin 'PSPath','PSParentPath','PSChildName','PSDrive','PSProvider' })) {
            $name = $p.Name
            $cmd  = [string]$p.Value
            $enabled = Get-StartupApprovedState -Hive $entry.Hive -Name $name -Area $entry.Area
            if (-not $IncludeDisabled -and -not $enabled) { continue }
            $exe,$args = Split-CommandLine $cmd
            if (-not $exe) { continue }
            if (-not (Test-Path $exe)) { continue }
            $items += [pscustomobject]@{
                Name       = $name
                Source     = "$($entry.Hive):$($entry.Area)"
                Command    = $cmd
                Path       = $exe
                Args       = $args
                Enabled    = $enabled
                Priority   = Guess-Priority -Name $name -Path $exe -Args $args
                KeyName    = $name
                Hive       = $entry.Hive
                Area       = $entry.Area
                FolderItem = $false
                LnkPath    = $null
            }
        }
    }

    # Startup folders (usuario y común)
    foreach ($sf in @(@{Folder=$Startup_User; Hive='HKCU'}, @{Folder=$Startup_Common; Hive='HKLM'})) {
        if (-not (Test-Path $sf.Folder)) { continue }
        Get-ChildItem -Path $sf.Folder -File -Filter *.lnk | ForEach-Object {
            $lnk = $_.FullName
            $name = $_.Name
            # Aprobación de carpeta se registra en HKCU
            $enabled = Get-StartupApprovedState -Hive 'HKCU' -Name $name -Area 'StartupFolder'
            if (-not $IncludeDisabled -and -not $enabled) { return }
            $res = Resolve-Shortcut -LnkPath $lnk
            if ($null -eq $res) { return }
            if (-not (Test-Path $res.Path)) { return }
            $items += [pscustomobject]@{
                Name       = $name
                Source     = "StartupFolder:$($sf.Folder)"
                Command    = "`"$($res.Path)`" $($res.Args)".Trim()
                Path       = $res.Path
                Args       = $res.Args
                Enabled    = $enabled
                Priority   = Guess-Priority -Name $name -Path $res.Path -Args $res.Args
                KeyName    = $name
                Hive       = $sf.Hive
                Area       = 'StartupFolder'
                FolderItem = $true
                LnkPath    = $lnk
            }
        }
    }

    $items | Sort-Object Priority, Name
}

function New-OrUpdate-StaggeredTask {
    param(
        [Parameter(Mandatory)]$Item,
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][int]$DelaySec
    )

    # Acción: si no hay argumentos, no pases -Argument
    $action = if ([string]::IsNullOrWhiteSpace($Item.Args)) {
        New-ScheduledTaskAction -Execute $Item.Path
    } else {
        New-ScheduledTaskAction -Execute $Item.Path -Argument $Item.Args
    }

    # Trigger: compatibilidad cruzada
    # 1º intentamos con -Delay (si tu módulo lo soporta). Si no, caemos a la propiedad .Delay con ISO 8601 (PT{S}S)
    $trigger = $null
    try {
        $trigger = New-ScheduledTaskTrigger -AtLogOn -Delay (New-TimeSpan -Seconds $DelaySec)
    } catch {
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        # ISO 8601 duration → evita el error XML "Delay:00:MM:SS"
        $trigger.Delay = ('PT{0}S' -f ([int]$DelaySec))
    }

    # Principal y ajustes
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -StartWhenAvailable -Compatibility Win8 -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 2)

    $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings

    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Register-ScheduledTask -TaskName $TaskName -InputObject $task -Force | Out-Null
        Write-Host ("Actualizada tarea: {0}  (Delay {1}s)  → {2} {3}" -f $TaskName,$DelaySec,$Item.Path,($Item.Args))
    } else {
        Register-ScheduledTask -TaskName $TaskName -InputObject $task | Out-Null
        Write-Host ("Creada tarea:    {0}  (Delay {1}s)  → {2} {3}" -f $TaskName,$DelaySec,$Item.Path,($Item.Args))
    }
}

function Compute-DelayMap {
    param([object[]]$Items,[int[]]$BaseDelays,[int]$Step)
    $map = @{}
    for ($prio=0; $prio -le 3; $prio++) {
        $bucket = $Items | Where-Object { $_.Priority -eq $prio } | Sort-Object Name
        $i = 0
        foreach ($it in $bucket) {
            $delay = $BaseDelays[$prio] + ($i * $Step)
            $map[$it.Name] = $delay
            $i++
        }
    }
    return $map
}

function Disable-OriginalStartup { param([object]$Item)
    Set-StartupApprovedState -Hive $Item.Hive -Name $Item.KeyName -Area $Item.Area -Enabled:$false
}
function Enable-OriginalStartup  { param([object]$Item)
    Set-StartupApprovedState -Hive $Item.Hive -Name $Item.KeyName -Area $Item.Area -Enabled:$true
}

function Start-StaggeredNow {
    param([string]$Prefix)
    Get-ScheduledTask | Where-Object { $_.TaskName -like "$Prefix`_*" } | ForEach-Object {
        Write-Host "Lanzando ahora: $($_.TaskName)"
        Start-ScheduledTask -TaskName $_.TaskName
    }
}

function Remove-StaggeredTasks {
    param([string]$Prefix)
    Get-ScheduledTask | Where-Object { $_.TaskName -like "$Prefix`_*" } | ForEach-Object {
        Write-Host "Eliminando: $($_.TaskName)"
        Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue
    }
}

# --- MAIN ---
if ($List) {
    $items = Get-StartupItems -IncludeDisabled:$IncludeDisabled
    if (-not $items) { Write-Host "No se detectaron elementos en Inicio (según filtros)."; exit }
    $delayMap = Compute-DelayMap -Items $items -BaseDelays $BaseDelays -Step $StepWithinBucket
    $items | Select-Object Name, Source,
        @{n='Enabled';e={$_.Enabled}},
        @{n='Priority';e={ switch($_.Priority){0{'Crítico'}1{'Alto'}2{'Medio'}3{'Bajo'}} }},
        @{n='Delay(s)';e={$delayMap[$_.Name]}},
        Path, Args |
        Format-Table -AutoSize
    exit
}
elseif ($Register) {
    Assert-Admin
    # Para registrar, tiene sentido incluir también los deshabilitados (por si ya deshabilitamos antes)
    $items = Get-StartupItems -IncludeDisabled:$true
    if (-not $items) { Write-Host "No hay nada que registrar."; exit }
    $delayMap = Compute-DelayMap -Items $items -BaseDelays $BaseDelays -Step $StepWithinBucket

    foreach ($it in $items) {
        $safeName = ($it.Name -replace '[^\w\-.]','_')
        $taskName = "$Prefix`_$safeName"
        $delay = $delayMap[$it.Name]
        New-OrUpdate-StaggeredTask -Item $it -TaskName $taskName -DelaySec $delay
        if ($DisableOriginals) { Disable-OriginalStartup -Item $it }
    }
    Write-Host "`n✅ Listo. Cierra sesión y vuelve a entrar para aplicar el arranque escalonado."
    exit
}
elseif ($Test) {
    Start-StaggeredNow -Prefix $Prefix
    exit
}
elseif ($Remove) {
    Assert-Admin
    if ($ReenableOriginalsOnRemove) {
        # Rehabilita todo lo detectado (incluye deshabilitados)
        $items = Get-StartupItems -IncludeDisabled:$true
        foreach ($it in $items) { Enable-OriginalStartup -Item $it }
        Write-Host "Rehabilitado el inicio original (StartupApproved) para elementos detectados."
    }
    Remove-StaggeredTasks -Prefix $Prefix
    Write-Host "✅ Tareas eliminadas."
    exit
}
else {
    Write-Host "Usa uno de los parámetros: -List [-IncludeDisabled]  |  -Register  |  -Test  |  -Remove"
}
