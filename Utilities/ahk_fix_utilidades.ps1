$enc = [System.Text.UTF8Encoding]::new($false)
$path = 'C:\Users\aitor.calero\iCloudDrive\02_Profesional_y_Proyectos\Proyectos_Desarrollo\AHK\modules\utilidades.ahk'
$content = '; ============================================================
; utilidades.ahk -- Fechas dinamicas, timestamps y utilidades
; AutoHotkey v2
; ============================================================

; --- Fecha y hora dinamica ---

; fechahoy -> dd/MM/yyyy  (ej: 26/03/2026)
:*:fechahoy:: {
    Send(FormatTime(A_Now, "dd/MM/yyyy"))
}

; fechaiso -> yyyy-MM-dd  (ej: 2026-03-26)
:*:fechaiso:: {
    Send(FormatTime(A_Now, "yyyy-MM-dd"))
}

; fechahora -> yyyy-MM-dd HH:mm
:*:fechahora:: {
    Send(FormatTime(A_Now, "yyyy-MM-dd HH:mm"))
}

; timestamp -> yyyyMMdd_HHmmss -- ideal para nombres de archivo unicos
:*:timestamp:: {
    Send(FormatTime(A_Now, "yyyyMMdd_HHmmss"))
}

; anyo -> ano en curso
:*:anyo:: {
    Send(FormatTime(A_Now, "yyyy"))
}

; Ctrl+Alt+R -> Recargar todos los modulos sin reiniciar sesion
^!r:: {
    Reload()
}

; Ctrl+Alt+S -> Suspender/reanudar todos los atajos
^!s:: {
    Suspend()
    if A_IsSuspended
        TrayTip("AHK", "Atajos SUSPENDIDOS", 2)
    else
        TrayTip("AHK", "Atajos ACTIVOS", 2)
}
'
[System.IO.File]::WriteAllText($path, $content, $enc)
Write-Host "[OK] utilidades.ahk corregido." -ForegroundColor Green
[System.IO.File]::ReadAllLines($path, $enc) | ForEach-Object { Write-Host "  $_" }
