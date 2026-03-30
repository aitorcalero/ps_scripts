 # Definir la ruta del escritorio
 $desktopPath = [Environment]::GetFolderPath("Desktop")

 # Definir las carpetas de destino y sus extensiones
 $folders = @{
     "Imágenes"  = @(".jpg", ".jpeg", ".png", ".gif", ".bmp", ".svg")
     "Documentos" = @(".pdf", ".docx", ".doc", ".txt", ".xlsx", ".pptx", ".odt")
     "Vídeos"     = @(".mp4", ".mov", ".avi", ".mkv")
     "Música"     = @(".mp3", ".wav", ".flac")
     "Comprimidos" = @(".zip", ".rar", ".7z", ".tar")
     "Ejecutables" = @(".exe", ".msi")
 }

 # Crear las carpetas si no existen
 foreach ($folderName in $folders.Keys) {
     $targetPath = Join-Path $desktopPath $folderName
     if (!(Test-Path $targetPath)) {
         New-Item -ItemType Directory -Path $targetPath | Out-Null
     }
 }

 # Mover archivos
 Get-ChildItem -Path $desktopPath -File | ForEach-Object {
     $file = $_
     $moved = $false

     foreach ($category in $folders.Keys) {
         if ($folders[$category] -contains $file.Extension.ToLower()) {
             Move-Item -Path $file.FullName -Destination (Join-Path $desktopPath $category)
             $moved = $true
             break
         }
     }
 }

 Write-Host "¡Escritorio organizado con éxito!" -ForegroundColor Green