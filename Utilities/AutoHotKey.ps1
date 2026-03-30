# Esperar a que el sistema esté 30 s idle
$IdleSeconds = 30

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class IdleCheck {
    [StructLayout(LayoutKind.Sequential)]
    struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }

    [DllImport("user32.dll")]
    static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    public static uint GetIdleTime() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf(lii);
        GetLastInputInfo(ref lii);
        return ((uint)Environment.TickCount - lii.dwTime);
    }
}
"@

while(([IdleCheck]::GetIdleTime() / 1000) -lt $IdleSeconds){
    Start-Sleep -Milliseconds 500
}

$TaskName = "AHK-Abreviaturas"

$ScriptPath = "C:\Users\aitor.calero\iCloud Drive\AHK\Abreviaturas.ahk"
$AhkExe = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"

$action = New-ScheduledTaskAction `
    -Execute $AhkExe `
    -Argument "`"$ScriptPath`""

$trigger = New-ScheduledTaskTrigger -AtLogOn

$settings = New-ScheduledTaskSettingsSet `
    -RunOnlyIfIdle `
    -IdleDuration (New-TimeSpan -Seconds 30) `
    -IdleWaitTimeout (New-TimeSpan -Minutes 10) `
    -MultipleInstances IgnoreNew

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -User $env:USERNAME `
    -RunLevel Limited