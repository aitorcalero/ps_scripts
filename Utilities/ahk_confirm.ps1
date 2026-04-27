$enc = [System.Text.UTF8Encoding]::new($false)
$base = 'C:\Users\aitor.calero\iCloudDrive\02_Profesional_y_Proyectos\Proyectos_Desarrollo\AHK\modules'
$files = @('snippets_texto.ahk','utilidades.ahk','ventanas.ahk')

foreach ($f in $files) {
    $path = Join-Path $base $f
    $content = [System.IO.File]::ReadAllText($path, $enc)
    $lines = $content -split "`n"
    Write-Host "--- $f ---" -ForegroundColor Yellow
    foreach ($line in $lines) {
        if ($line.Length -gt 0 -and $line -notmatch '^;' -and $line -notmatch '^\s*$') {
            Write-Host "  $line"
        }
    }
    Write-Host ""
}
