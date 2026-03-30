<#
.SYNOPSIS
Extrae el cuerpo de texto plano de archivos .eml y lo guarda en un archivo de texto.

.DESCRIPTION
Este script lee uno o más archivos .eml, busca la sección de texto plano (text/plain)
en el contenido MIME y extrae ese texto. Si no encuentra una sección de texto plano,
intenta extraer el cuerpo del mensaje de la manera más simple.

.PARAMETER Path
Ruta a uno o más archivos .eml. Se pueden usar comodines (ej: C:\Correos\*.eml).
Si se proporciona un directorio, buscará todos los archivos .eml dentro.

.PARAMETER OutputFile
Ruta al archivo de texto donde se guardará el texto extraído.
Si el archivo ya existe, el nuevo texto se añadirá al final.

.EXAMPLE
.\Extract-EmlText.ps1 -Path "C:\Correos\mi_correo.eml" -OutputFile "C:\Resultados\texto_extraido.txt"

.EXAMPLE
.\Extract-EmlText.ps1 -Path "C:\Correos\*.eml" -OutputFile "C:\Resultados\todos_los_textos.txt"

.EXAMPLE
# Si solo se proporciona un directorio, busca todos los .eml dentro
.\Extract-EmlText.ps1 -Path "C:\Correos\" -OutputFile "C:\Resultados\todos_los_textos.txt"
#>
param(
    [Parameter(Mandatory=$true)]
    [string[]]$Path,

    [Parameter(Mandatory=$true)]
    [string]$OutputFile
)

function Get-EmlBodyText {
    param(
        [Parameter(Mandatory=$true)]
        [string]$EmlPath
    )

    Write-Host "Procesando archivo: $EmlPath" -ForegroundColor Cyan

    # Leer el contenido completo del archivo .eml
    $content = Get-Content -Path $EmlPath -Raw

    # 1. Intentar encontrar el cuerpo de texto plano (text/plain)
    # El patrón busca la cabecera Content-Type: text/plain y captura el contenido hasta el siguiente límite MIME.
    # Esto es más robusto para correos multipart.
    $plainTextMatch = $content | Select-String -Pattern 'Content-Type: text/plain;.*?\r?\n\r?\n(.*?)(?=--_|=--_|$)' -Singleline

    if ($plainTextMatch) {
        $body = $plainTextMatch.Matches[0].Groups[1].Value.Trim()
        
        # Decodificar si está codificado en Quoted-Printable o Base64
        if ($content -match 'Content-Transfer-Encoding: quoted-printable') {
            # Quoted-Printable decoding (simple implementation, may need external module for full support)
            $body = $body -replace '=\r?\n', '' # Quitar saltos de línea suaves
            Write-Host "Advertencia: El contenido está codificado en Quoted-Printable. Se realiza una decodificación básica." -ForegroundColor Yellow
        } elseif ($content -match 'Content-Transfer-Encoding: base64') {
            # Base64 decoding
            try {
                $bytes = [System.Convert]::FromBase64String($body)
                $body = [System.Text.Encoding]::UTF8.GetString($bytes)
                Write-Host "Contenido Base64 decodificado." -ForegroundColor Green
            } catch {
                Write-Host "Error al decodificar Base64. Usando el texto sin decodificar." -ForegroundColor Red
            }
        }
        
        # Limpiar el texto de posibles cabeceras o pies de página MIME remanentes
        $body = $body -replace '(?s)^.*Content-Type: text/plain;.*?\r?\n\r?\n', ''
        $body = $body -replace '(?s)--[a-zA-Z0-9_]+--.*$', ''
        $body = $body.Trim()
        
        return $body
    }

    # 2. Si no se encuentra text/plain, intentar una extracción simple del cuerpo
    # Buscar el final de las cabeceras (la primera línea vacía) y tomar el resto.
    $body = $content -split "`r?`n`r?`n", 2 | Select-Object -Last 1
    
    # Limpiar el texto de posibles límites MIME o contenido HTML si es un correo simple
    $body = $body -replace '(?s)<html.*?>.*?</html>', '' # Quitar HTML si está presente
    $body = $body -replace '(?s)--[a-zA-Z0-9_]+.*$', '' # Quitar límites MIME
    $body = $body.Trim()

    if ([string]::IsNullOrWhiteSpace($body)) {
        Write-Host "No se pudo extraer el cuerpo de texto plano de forma fiable." -ForegroundColor Red
        return "--- ERROR: No se pudo extraer el texto del archivo $EmlPath ---"
    }
    
    Write-Host "Extracción simple del cuerpo del mensaje." -ForegroundColor Yellow
    return $body
}

# --- Lógica principal del script ---

# 1. Manejar el archivo de salida: Asegurar que el directorio exista y obtener la ruta absoluta.
$outputFilePath = Resolve-Path -Path $OutputFile -ErrorAction SilentlyContinue
if (-not $outputFilePath) {
    # Si la ruta no existe, intentamos crear el directorio si es necesario
    $outputDir = Split-Path -Path $OutputFile -Parent
    if (-not (Test-Path -Path $outputDir -PathType Container)) {
        Write-Host "Creando directorio de salida: $outputDir" -ForegroundColor Yellow
        New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
    }
    # Si solo se proporcionó un nombre de archivo, PowerShell lo resolverá en el directorio actual.
    $outputFilePath = $OutputFile
}

# Limpiar el archivo de salida antes de empezar
Clear-Content -Path $outputFilePath -Force

# 2. Resolver las rutas de los archivos .eml, filtrando directorios y buscando .eml si se da un directorio.
$emlFiles = @()
foreach ($p in $Path) {
    $item = Get-Item -Path $p -ErrorAction SilentlyContinue
    if ($item -is [System.IO.DirectoryInfo]) {
        # Si es un directorio, buscar todos los .eml dentro
        $emlFiles += Get-ChildItem -Path $item.FullName -Filter "*.eml" -File -Recurse:$false
    } elseif ($item -is [System.IO.FileInfo] -and $item.Extension -ceq ".eml") {
        # Si es un archivo .eml
        $emlFiles += $item
    } elseif ($p -like "*.*") {
        # Si tiene comodines (ej: *.eml)
        $emlFiles += Get-ChildItem -Path $p -File -ErrorAction SilentlyContinue
    } else {
        Write-Host "Advertencia: La ruta '$p' no es un archivo .eml ni un directorio válido. Saltando." -ForegroundColor Yellow
    }
}

if ($emlFiles.Count -eq 0) {
    Write-Host "Error: No se encontraron archivos .eml para procesar en las rutas proporcionadas." -ForegroundColor Red
    exit 1
}

foreach ($file in $emlFiles) {
    $extractedText = Get-EmlBodyText -EmlPath $file.FullName

    # Formato de salida
    $output = @"
================================================================================
ARCHIVO: $($file.Name)
RUTA: $($file.FullName)
FECHA DE EXTRACCIÓN: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
================================================================================

$extractedText

"@

    # Escribir en el archivo de salida
    Add-Content -Path $outputFilePath -Value $output
}

Write-Host "Proceso completado. El texto extraído se ha guardado en: $outputFilePath" -ForegroundColor Green