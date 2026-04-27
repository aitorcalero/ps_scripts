# ============================================================
# ahk_fix_encoding.ps1
# Sobreescribe los módulos con caracteres especiales corruptos.
# Usa [System.IO.File]::WriteAllText con UTF-8 sin BOM,
# que es lo que AHK v2 espera por defecto.
# ============================================================

$modulesDir = "C:\Users\aitor.calero\iCloudDrive\02_Profesional_y_Proyectos\Proyectos_Desarrollo\AHK\modules"
$enc = [System.Text.UTF8Encoding]::new($false)  # UTF-8 sin BOM

# ── snippets_texto.ahk ────────────────────────────────────────
$snippetsTexto = @'
; ============================================================
; snippets_texto.ahk — Expansiones de texto y frases frecuentes
; AutoHotkey v2
; ============================================================

; --- Saludos y cierres ---
:*:ht::Hola a todos,
:*:ha::Hola a ambos,
:*:us::Un saludo,
:*:mg::Muchas gracias.
:*:kr::Thank you very much and kind regards,
:*:imho::En mi opinión

; --- Cierres compuestos ---
:*:mgus::Muchas gracias.{Enter}{Enter}Un saludo.
:*:htmg::Hola a todos,{Enter}{Enter}{Enter}Muchas gracias{Enter}{Enter}Un saludo.
:*:htus::Hola a todos,{Enter}{Enter}{Enter}{Enter}{Enter}{Enter}Un saludo.

; --- Frases de cortesía profesional ---
:*:qd::Quedamos a vuestra disposición para cualquier aclaración necesaria.
:*:acla::Si necesitáis alguna aclaración adicional no dudes en ponerte en contacto conmigo.
:*:tel::He intentado contactar contigo telefónicamente pero no ha sido posible.

; --- Datos de contacto e identidad ---
:*:acg::Aitor Calero García
:*:em::aitor.calero@gmail.com
:*:emr::aitor.calero@esri.es
:*:direcc::Gutierre de Cetina 30. Esc Izquierda. 2ºB{Enter}28017 Madrid

; --- Organizaciones ---
:*:ee::Esri España
:*:ei::Esri Inc.
:*:fed::Federación Española de Enfermedades Metabólicas Hereditarias (FEEMH)

; --- Productos ArcGIS ---
:*:agol::ArcGIS Online
:*:agen::ArcGIS Enterprise

; --- RGPD / baja de listas ---
:*:rug::Por favor, ruego sea eliminado completamente de esta lista de distribución según mis derechos recogidos en la RGPD
:*:rug_en::Please, I request you to be completely removed from this distribution list according to my rights under the European GDPR
'@

# ── utilidades.ahk ────────────────────────────────────────────
$utilidades = @'
; ============================================================
; utilidades.ahk — Fechas dinámicas, timestamps y utilidades
; AutoHotkey v2
; ============================================================

; --- Fecha y hora dinámica ---

; fechahoy → dd/MM/yyyy  (ej: 26/03/2026)
:*:fechahoy:: {
    fecha := FormatTime(A_Now, "dd/MM/yyyy")
    Send fecha
}

; fechaiso → yyyy-MM-dd  (ej: 2026-03-26)
:*:fechaiso:: {
    fecha := FormatTime(A_Now, "yyyy-MM-dd")
    Send fecha
}

; fechahora → yyyy-MM-dd HH:mm
:*:fechahora:: {
    fecha := FormatTime(A_Now, "yyyy-MM-dd HH:mm")
    Send fecha
}

; timestamp → yyyyMMdd_HHmmss — ideal para nombres de archivo únicos
:*:timestamp:: {
    ts := FormatTime(A_Now, "yyyyMMdd_HHmmss")
    Send ts
}

; anyo → año en curso
:*:anyo:: {
    Send FormatTime(A_Now, "yyyy")
}

; --- Ctrl+Alt+R → Recargar todos los módulos sin reiniciar sesión ---
^!r:: {
    Reload
}

; --- Ctrl+Alt+S → Suspender/reanudar todos los atajos ---
^!s:: {
    Suspend
    if A_IsSuspended
        TrayTip "AHK", "Atajos SUSPENDIDOS", 2
    else
        TrayTip "AHK", "Atajos ACTIVOS", 2
}
'@

# ── ventanas.ahk ──────────────────────────────────────────────
$ventanas = @'
; ============================================================
; ventanas.ahk — Gestión de ventanas y lanzamiento de apps
; AutoHotkey v2
; Si la app ya está abierta, la trae al frente; si no, la lanza.
; ============================================================

; --- Win+T → Terminal (Windows Terminal) ---
#t:: {
    if WinExist("ahk_exe WindowsTerminal.exe")
        WinActivate
    else
        Run "wt.exe"
}

; --- Win+C → VSCode ---
#c:: {
    if WinExist("ahk_exe Code.exe")
        WinActivate
    else
        Run "code"
}

; --- Win+B → Navegador (Edge) ---
#b:: {
    if WinExist("ahk_exe msedge.exe")
        WinActivate
    else
        Run "msedge.exe"
}

; --- Win+O → Outlook ---
#o:: {
    if WinExist("ahk_exe OUTLOOK.EXE")
        WinActivate
    else
        Run "outlook.exe"
}

; --- Win+P → ArcGIS Pro ---
#p:: {
    if WinExist("ahk_exe ArcGISPro.exe")
        WinActivate
    else
        Run "C:\Program Files\ArcGIS\Pro\bin\ArcGISPro.exe"
}

; --- Ctrl+Alt+T → Terminal en la carpeta activa del Explorador ---
^!t:: {
    explorerHwnd := WinExist("ahk_class CabinetWClass")
    if explorerHwnd {
        for window in ComObject("Shell.Application").Windows() {
            if window.HWND = explorerHwnd {
                path := window.Document.Folder.Self.Path
                Run 'wt.exe -d "' path '"'
                return
            }
        }
    }
    Run "wt.exe"
}
'@

# ── Escribir ficheros ─────────────────────────────────────────
[System.IO.File]::WriteAllText("$modulesDir\snippets_texto.ahk", $snippetsTexto, $enc)
Write-Host "[OK] snippets_texto.ahk corregido." -ForegroundColor Green

[System.IO.File]::WriteAllText("$modulesDir\utilidades.ahk", $utilidades, $enc)
Write-Host "[OK] utilidades.ahk corregido (encoding + bug SendInput)." -ForegroundColor Green

[System.IO.File]::WriteAllText("$modulesDir\ventanas.ahk", $ventanas, $enc)
Write-Host "[OK] ventanas.ahk corregido." -ForegroundColor Green

# ── Verificar encoding ────────────────────────────────────────
Write-Host ""
Write-Host "=== Verificación de encoding (primeras 3 líneas de cada fichero) ===" -ForegroundColor Cyan
foreach ($f in @("snippets_texto.ahk","utilidades.ahk","ventanas.ahk")) {
    Write-Host "--- $f ---" -ForegroundColor Yellow
    [System.IO.File]::ReadAllLines("$modulesDir\$f", $enc) | Select-Object -First 3
}

Write-Host ""
Write-Host "=== LISTO. Recarga con Ctrl+Alt+R ===" -ForegroundColor Green
