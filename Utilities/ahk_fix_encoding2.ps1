# ahk_fix_encoding2.ps1 -- generado con escape Unicode puro (sin caracteres no-ASCII en el script)
$modulesDir = "C:\Users\aitor.calero\iCloudDrive\02_Profesional_y_Proyectos\Proyectos_Desarrollo\AHK\modules"
$enc = [System.Text.UTF8Encoding]::new($false)

# --- snippets_texto.ahk ---
$content = '; ============================================================
; snippets_texto.ahk ' + [char]8212 + ' Expansiones de texto y frases frecuentes
; AutoHotkey v2
; ============================================================

; --- Saludos y cierres ---
:*:ht::Hola a todos,
:*:ha::Hola a ambos,
:*:us::Un saludo,
:*:mg::Muchas gracias.
:*:kr::Thank you very much and kind regards,
:*:imho::En mi opini' + [char]243 + 'n

; --- Cierres compuestos ---
:*:mgus::Muchas gracias.{Enter}{Enter}Un saludo.
:*:htmg::Hola a todos,{Enter}{Enter}{Enter}Muchas gracias{Enter}{Enter}Un saludo.
:*:htus::Hola a todos,{Enter}{Enter}{Enter}{Enter}{Enter}{Enter}Un saludo.

; --- Frases de cortes' + [char]237 + 'a profesional ---
:*:qd::Quedamos a vuestra disposici' + [char]243 + 'n para cualquier aclaraci' + [char]243 + 'n necesaria.
:*:acla::Si necesit' + [char]225 + 'is alguna aclaraci' + [char]243 + 'n adicional no dudes en ponerte en contacto conmigo.
:*:tel::He intentado contactar contigo telef' + [char]243 + 'nicamente pero no ha sido posible.

; --- Datos de contacto e identidad ---
:*:acg::Aitor Calero Garc' + [char]237 + 'a
:*:em::aitor.calero@gmail.com
:*:emr::aitor.calero@esri.es
:*:direcc::Gutierre de Cetina 30. Esc Izquierda. 2' + [char]186 + 'B{Enter}28017 Madrid

; --- Organizaciones ---
:*:ee::Esri Espa' + [char]241 + 'a
:*:ei::Esri Inc.
:*:fed::Federaci' + [char]243 + 'n Espa' + [char]241 + 'ola de Enfermedades Metab' + [char]243 + 'licas Hereditarias (FEEMH)

; --- Productos ArcGIS ---
:*:agol::ArcGIS Online
:*:agen::ArcGIS Enterprise

; --- RGPD / baja de listas ---
:*:rug::Por favor, ruego sea eliminado completamente de esta lista de distribuci' + [char]243 + 'n seg' + [char]250 + 'n mis derechos recogidos en la RGPD
:*:rug_en::Please, I request you to be completely removed from this distribution list according to my rights under the European GDPR
'
[System.IO.File]::WriteAllText("$modulesDir\snippets_texto.ahk", $content, $enc)
Write-Host "[OK] snippets_texto.ahk escrito." -ForegroundColor Green

# --- utilidades.ahk ---
$content = '; ============================================================
; utilidades.ahk ' + [char]8212 + ' Fechas din' + [char]225 + 'micas, timestamps y utilidades
; AutoHotkey v2
; ============================================================

; --- Fecha y hora din' + [char]225 + 'mica ---

; fechahoy ' + [char]8594 + ' dd/MM/yyyy  (ej: 26/03/2026)
:*:fechahoy:: {
    fecha := FormatTime(A_Now, "dd/MM/yyyy")
    Send fecha
}

; fechaiso ' + [char]8594 + ' yyyy-MM-dd  (ej: 2026-03-26)
:*:fechaiso:: {
    fecha := FormatTime(A_Now, "yyyy-MM-dd")
    Send fecha
}

; fechahora ' + [char]8594 + ' yyyy-MM-dd HH:mm
:*:fechahora:: {
    fecha := FormatTime(A_Now, "yyyy-MM-dd HH:mm")
    Send fecha
}

; timestamp ' + [char]8594 + ' yyyyMMdd_HHmmss ' + [char]8212 + ' ideal para nombres de archivo ' + [char]250 + 'nicos
:*:timestamp:: {
    ts := FormatTime(A_Now, "yyyyMMdd_HHmmss")
    Send ts
}

; anyo ' + [char]8594 + ' a' + [char]241 + 'o en curso
:*:anyo:: {
    Send FormatTime(A_Now, "yyyy")
}

; --- Ctrl+Alt+R ' + [char]8594 + ' Recargar todos los m' + [char]243 + 'dulos sin reiniciar sesi' + [char]243 + 'n ---
    Reload
}

; --- Ctrl+Alt+S ' + [char]8594 + ' Suspender/reanudar todos los atajos ---
    Suspend
    if A_IsSuspended
        TrayTip "AHK", "Atajos SUSPENDIDOS", 2
    else
        TrayTip "AHK", "Atajos ACTIVOS", 2
}
'
[System.IO.File]::WriteAllText("$modulesDir\utilidades.ahk", $content, $enc)
Write-Host "[OK] utilidades.ahk escrito." -ForegroundColor Green

# --- ventanas.ahk ---
$content = '; ============================================================
; ventanas.ahk ' + [char]8212 + ' Gesti' + [char]243 + 'n de ventanas y lanzamiento de apps
; AutoHotkey v2
; Si la app ya est' + [char]225 + ' abierta, la trae al frente; si no, la lanza.
; ============================================================

; --- Win+T ' + [char]8594 + ' Terminal (Windows Terminal) ---
#t:: {
    if WinExist("ahk_exe WindowsTerminal.exe")
        WinActivate
    else
        Run "wt.exe"
}

; --- Win+C ' + [char]8594 + ' VSCode ---
#c:: {
    if WinExist("ahk_exe Code.exe")
        WinActivate
    else
        Run "code"
}

; --- Win+B ' + [char]8594 + ' Navegador (Edge) ---
#b:: {
    if WinExist("ahk_exe msedge.exe")
        WinActivate
    else
        Run "msedge.exe"
}

; --- Win+O ' + [char]8594 + ' Outlook ---
#o:: {
    if WinExist("ahk_exe OUTLOOK.EXE")
        WinActivate
    else
        Run "outlook.exe"
}

; --- Win+P ' + [char]8594 + ' ArcGIS Pro ---
#p:: {
    if WinExist("ahk_exe ArcGISPro.exe")
        WinActivate
    else
        Run "C:\Program Files\ArcGIS\Pro\bin\ArcGISPro.exe"
}

; --- Ctrl+Alt+T ' + [char]8594 + ' Terminal en la carpeta activa del Explorador ---
    explorerHwnd := WinExist("ahk_class CabinetWClass")
    if explorerHwnd {
        for window in ComObject("Shell.Application").Windows() {
            if window.HWND = explorerHwnd {
                path := window.Document.Folder.Self.Path
                Run ' + [char]39 + 'wt.exe -d "' + [char]39 + ' path ' + [char]39 + '"' + [char]39 + '
                return
            }
        }
    }
    Run "wt.exe"
}
'
[System.IO.File]::WriteAllText("$modulesDir\ventanas.ahk", $content, $enc)
Write-Host "[OK] ventanas.ahk escrito." -ForegroundColor Green

Write-Host ""
Write-Host "=== Verificacion (lineas con tildes/enie) ===" -ForegroundColor Cyan
foreach ($f in @("snippets_texto.ahk","utilidades.ahk","ventanas.ahk")) {
    Write-Host "--- $f ---" -ForegroundColor Yellow
    $lines2 = [System.IO.File]::ReadAllLines("$modulesDir\$f", $enc)
    $lines2 | Where-Object { $_ -match $([char]0x00f3) } | Select-Object -First 5 | ForEach-Object { Write-Host "  $_" }
}
Write-Host ""
Write-Host "LISTO. Recarga con Ctrl+Alt+R" -ForegroundColor Green