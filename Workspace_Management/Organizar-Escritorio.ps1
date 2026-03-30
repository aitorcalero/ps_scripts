# Organizar-Escritorio.ps1
# Versión 1.0 – Organiza el escritorio por tipo de archivo
# Autor: Aitor + ChatGPT Forge

$Desktop = [Environment]::GetFolderPath("Desktop")

# Rutas destino (puedes personalizar)
$DestinoDocs   = "$Desktop\Documentos"
$DestinoImg    = "$Desktop\Imágenes"
$DestinoVideos = "$Desktop\Vídeos"
$DestinoOtros  = "$Desktop\Otros"

# Crear carpetas si no existen
foreach ($folder in @($DestinoDocs, $DestinoImg, $DestinoVideos, $DestinoOtros)) {
    if (-not (Test-Path $folder)) { New-Item -Path $folder -ItemType Directory | Out-Null }
}

# Reglas por extensión
$Reglas = @{
    $DestinoDocs   = @('pdf','docx','xlsx','pptx','txt','csv')
    $DestinoImg    = @('jpg','jpeg','png','gif','bmp','svg','heic')
    $DestinoVideos = @('mp4','mov','avi','mkv')
}

# Mover archivos
Get-ChildItem -Path $Desktop -File | ForEach-Object {
    $ext = $_.Extension.TrimStart('.').ToLower()

    $Destino = $null
    foreach ($carpeta in $Reglas.Keys) {
        if ($Reglas[$carpeta] -contains $ext) { $Destino = $carpeta; break }
    }

    if (-not $Destino) { $Destino = $DestinoOtros }

    try {
        Move-Item -Path $_.FullName -Destination $Destino -Force
        Write-Host "Movido: $($_.Name) → $Destino"
    } catch {
        Write-Warning "No se pudo mover $($_.Name): $_"
    }
}
