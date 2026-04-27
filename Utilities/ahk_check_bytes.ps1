# Verifica el encoding real de los ficheros leyendo los primeros bytes
# y muestra el contenido forzando UTF-8 explícitamente

$modulesDir = "C:\Users\aitor.calero\iCloudDrive\02_Profesional_y_Proyectos\Proyectos_Desarrollo\AHK\modules"
$enc = [System.Text.UTF8Encoding]::new($false)

foreach ($f in @("snippets_texto.ahk", "utilidades.ahk", "ventanas.ahk")) {
    $path = "$modulesDir\$f"
    Write-Host "--- $f ---" -ForegroundColor Yellow

    # Leer primeros 4 bytes para detectar BOM
    $bytes = [System.IO.File]::ReadAllBytes($path) | Select-Object -First 4
    Write-Host ("  Primeros bytes (hex): " + ($bytes | ForEach-Object { $_.ToString("X2") }) -join " ")

    # Leer como UTF-8 y mostrar líneas con tildes/ñ
    $lines = [System.IO.File]::ReadAllLines($path, $enc)
    $special = $lines | Where-Object { $_ -match '[áéíóúüñÁÉÍÓÚÜÑº°]' }
    Write-Host "  Líneas con caracteres especiales:"
    $special | ForEach-Object { Write-Host "    $_" }
    Write-Host ""
}
