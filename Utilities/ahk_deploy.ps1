# ============================================================
# ahk_deploy.ps1 — Despliega la estructura modular AHK
# Hace backup del Abreviaturas.ahk original antes de sobreescribir
# ============================================================

$ahkBase = "C:\Users\aitor.calero\iCloudDrive\02_Profesional_y_Proyectos\Proyectos_Desarrollo\AHK"
$modulesDir = Join-Path $ahkBase "modules"

# 1. Backup del script original
$backupPath = Join-Path $ahkBase ("Abreviaturas.ahk.bak_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
if (Test-Path (Join-Path $ahkBase "Abreviaturas.ahk")) {
    Copy-Item (Join-Path $ahkBase "Abreviaturas.ahk") $backupPath
    Write-Host "[OK] Backup creado: $backupPath" -ForegroundColor Green
}

# 2. Crear carpeta modules si no existe
if (-not (Test-Path $modulesDir)) {
    New-Item -ItemType Directory -Path $modulesDir -Force | Out-Null
    Write-Host "[OK] Carpeta modules creada." -ForegroundColor Green
} else {
    Write-Host "[OK] Carpeta modules ya existe." -ForegroundColor Green
}

# 3. Escribir Abreviaturas.ahk (punto de entrada)
Set-Content -Path (Join-Path $ahkBase "Abreviaturas.ahk") -Encoding UTF8 -Value @'
; ============================================================
; Abreviaturas.ahk — Punto de entrada principal
; AutoHotkey v2
; Estructura modular: cada módulo es independiente y se puede
; activar o desactivar comentando la línea #Include correspondiente.
; ============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

; --- Módulos ---
#Include modules\snippets_texto.ahk
#Include modules\snippets_codigo.ahk
#Include modules\ventanas.ahk
#Include modules\utilidades.ahk
#Include modules\portapapeles.ahk
'@
Write-Host "[OK] Abreviaturas.ahk (punto de entrada) escrito." -ForegroundColor Green

# 4. Escribir módulo snippets_texto.ahk
Set-Content -Path (Join-Path $modulesDir "snippets_texto.ahk") -Encoding UTF8 -Value @'
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
Write-Host "[OK] snippets_texto.ahk escrito." -ForegroundColor Green

# 5. Escribir módulo snippets_codigo.ahk
Set-Content -Path (Join-Path $modulesDir "snippets_codigo.ahk") -Encoding UTF8 -Value @'
; ============================================================
; snippets_codigo.ahk — Snippets técnicos y de código
; AutoHotkey v2
; ============================================================

; --- Python ---
:*:pyimp::import os{Enter}import sys{Enter}import json{Enter}
:*:pyenv::if __name__ == "__main__":{Enter}    pass
:*:pylog::import logging{Enter}logging.basicConfig(level=logging.INFO){Enter}logger = logging.getLogger(__name__)

; --- Git (para pegar en terminal) ---
:*:gst::git status
:*:gpl::git pull
:*:gps::git push
:*:gcm::git commit -m ""
:*:glog::git log --oneline --graph --decorate -20

; --- Markdown ---
:*:mdtable::| Columna 1 | Columna 2 | Columna 3 |{Enter}|---|---|---|{Enter}| | | |
:*:mdcode::```{Enter}{Enter}```
:*:mdbold::**texto**
:*:mdlink::[texto](url)

; --- ArcGIS REST API ---
:*:arcrest::https://www.arcgis.com/sharing/rest
:*:arctoken::/generateToken?f=json
:*:arcquery::?where=1%3D1&outFields=*&f=json

; --- URLs frecuentes ---
:*:agolurl::https://esriespa.maps.arcgis.com
:*:feemhurl::https://www.feemh.es

; --- PowerShell snippets ---
:*:pswhere::Get-Command  | Select-Object -ExpandProperty Source
:*:psenv::$env:
:*:psexec::powershell -NoProfile -ExecutionPolicy Bypass -File ""
'@
Write-Host "[OK] snippets_codigo.ahk escrito." -ForegroundColor Green

# 6. Escribir módulo ventanas.ahk
Set-Content -Path (Join-Path $modulesDir "ventanas.ahk") -Encoding UTF8 -Value @'
; ============================================================
; ventanas.ahk — Gestión de ventanas y lanzamiento de apps
; AutoHotkey v2
; Atajos: Win+letra para enfocar o lanzar aplicaciones frecuentes.
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
Write-Host "[OK] ventanas.ahk escrito." -ForegroundColor Green

# 7. Escribir módulo utilidades.ahk
Set-Content -Path (Join-Path $modulesDir "utilidades.ahk") -Encoding UTF8 -Value @'
; ============================================================
; utilidades.ahk — Fechas dinámicas, timestamps y utilidades
; AutoHotkey v2
; ============================================================

; --- Fecha y hora dinámica ---

; :*:fechahoy:: → dd/MM/yyyy  (ej: 26/03/2026)
:*:fechahoy:: {
    SendInput FormatTime(A_Now, "dd/MM/yyyy")
}

; :*:fechaiso:: → yyyy-MM-dd  (ej: 2026-03-26)
:*:fechaiso:: {
    SendInput FormatTime(A_Now, "yyyy-MM-dd")
}

; :*:fechahora:: → yyyy-MM-dd HH:mm
:*:fechahora:: {
    SendInput FormatTime(A_Now, "yyyy-MM-dd HH:mm")
}

; :*:timestamp:: → yyyyMMdd_HHmmss — ideal para nombres de archivo únicos
:*:timestamp:: {
    SendInput FormatTime(A_Now, "yyyyMMdd_HHmmss")
}

; :*:anyo:: → año en curso
:*:anyo:: {
    SendInput FormatTime(A_Now, "yyyy")
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
Write-Host "[OK] utilidades.ahk escrito." -ForegroundColor Green

# 8. Escribir módulo portapapeles.ahk
Set-Content -Path (Join-Path $modulesDir "portapapeles.ahk") -Encoding UTF8 -Value @'
; ============================================================
; portapapeles.ahk — Transformaciones sobre texto seleccionado
; AutoHotkey v2
; Selecciona texto, pulsa el atajo, el texto se transforma y se pega.
; ============================================================

; --- Ctrl+Alt+U → MAYÚSCULAS ---
^!u:: {
    saved := A_Clipboard
    A_Clipboard := ""
    Send "^c"
    ClipWait 1
    A_Clipboard := StrUpper(A_Clipboard)
    Send "^v"
    Sleep 200
    A_Clipboard := saved
}

; --- Ctrl+Alt+L → minúsculas ---
^!l:: {
    saved := A_Clipboard
    A_Clipboard := ""
    Send "^c"
    ClipWait 1
    A_Clipboard := StrLower(A_Clipboard)
    Send "^v"
    Sleep 200
    A_Clipboard := saved
}

; --- Ctrl+Alt+M → Envolver URL seleccionada en enlace Markdown [url](url) ---
^!m:: {
    saved := A_Clipboard
    A_Clipboard := ""
    Send "^c"
    ClipWait 1
    url := Trim(A_Clipboard)
    A_Clipboard := "[" url "](" url ")"
    Send "^v"
    Sleep 200
    A_Clipboard := saved
}
'@
Write-Host "[OK] portapapeles.ahk escrito." -ForegroundColor Green

# 9. Verificar estructura final
Write-Host ""
Write-Host "=== ESTRUCTURA FINAL ===" -ForegroundColor Cyan
Get-ChildItem $ahkBase -Recurse | Select-Object FullName | Format-Table -AutoSize

Write-Host ""
Write-Host "=== DESPLIEGUE COMPLETADO ===" -ForegroundColor Green
Write-Host "Recarga el script AHK con Ctrl+Alt+R o reinicia sesión."
