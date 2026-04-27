$enc = [System.Text.UTF8Encoding]::new($false)
$path = 'C:\Users\aitor.calero\iCloudDrive\02_Profesional_y_Proyectos\Proyectos_Desarrollo\AHK\modules\ventanas.ahk'
$content = '; ============================================================
; ventanas.ahk -- Gestion de ventanas y lanzamiento de apps
; AutoHotkey v2
; Si la app ya esta abierta, la trae al frente; si no, la lanza.
; ============================================================

; --- Win+T -> Terminal (Windows Terminal) ---
#t:: {
    if WinExist("ahk_exe WindowsTerminal.exe")
        WinActivate
    else
        Run "wt.exe"
}

; --- Win+C -> VSCode ---
#c:: {
    if WinExist("ahk_exe Code.exe")
        WinActivate
    else
        Run "code"
}

; --- Win+B -> Navegador (Edge) ---
#b:: {
    if WinExist("ahk_exe msedge.exe")
        WinActivate
    else
        Run "msedge.exe"
}

; --- Win+O -> Outlook ---
#o:: {
    if WinExist("ahk_exe OUTLOOK.EXE")
        WinActivate
    else
        Run "outlook.exe"
}

; --- Win+P -> ArcGIS Pro ---
#p:: {
    if WinExist("ahk_exe ArcGISPro.exe")
        WinActivate
    else
        Run "C:\Program Files\ArcGIS\Pro\bin\ArcGISPro.exe"
}

; --- Ctrl+Alt+T -> Terminal en la carpeta activa del Explorador ---
^!t:: {
    local path := ""
    for window in ComObject("Shell.Application").Windows() {
        try {
            if window.HWND = WinExist("ahk_class CabinetWClass") {
                path := window.Document.Folder.Self.Path
                break
            }
        }
    }
    if (path != "")
        Run ' + [char]39 + 'wt.exe -d "' + [char]39 + ' path ' + [char]39 + '"' + [char]39 + '
    else
        Run "wt.exe"
}
'
[System.IO.File]::WriteAllText($path, $content, $enc)
Write-Host "[OK] ventanas.ahk corregido." -ForegroundColor Green
Write-Host ""
Write-Host "Contenido escrito:" -ForegroundColor Cyan
[System.IO.File]::ReadAllLines($path, $enc) | ForEach-Object { Write-Host "  $_" }
