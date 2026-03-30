<#
Organizar-Descargas.ps1 (v2.0)
Reglas:
- Carpetas "grandes" en el raíz de Descargas (tamaño recursivo ≥ umbral) -> mover carpeta completa a "_Grandes".
- Archivos sueltos en el raíz de Descargas:
    * si comprimidos (zip/rar/7z/tar/gz/bz2/xz/iso) y < umbral -> "Comprimidos"
    * si tamaño ≥ umbral -> "_Grandes"
    * resto -> categoría por tipo (Documentos, Imágenes, Vídeo, Audio, Código, Instaladores, Torrents, Texto, Otros)
- No se tocan archivos dentro de subcarpetas.
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [double] $SizeThresholdGB = 1.0  # umbral archivos y carpetas
)

# --- Helpers ----------------------------------------------------
function Get-DownloadsPath {
    try { $p=[Environment]::GetFolderPath('Downloads'); if($p -and (Test-Path $p)){return $p} } catch {}
    $fb = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'
    if (Test-Path $fb) { return $fb }
    throw "No se pudo resolver la ruta de Descargas."
}

function New-UniquePath([Parameter(Mandatory)][string]$TargetPath) {
    if (-not (Test-Path $TargetPath)) { return $TargetPath }
    $dir  = Split-Path $TargetPath -Parent
    $base = [IO.Path]::GetFileNameWithoutExtension($TargetPath)
    $ext  = [IO.Path]::GetExtension($TargetPath)
    $i=1; do { $cand = Join-Path $dir ("{0} ({1}){2}" -f $base,$i,$ext); $i++ } while (Test-Path $cand)
    $cand
}

function Get-FolderSizeBytes([Parameter(Mandatory)][string]$Path) {
    $total = 0L
    Get-ChildItem -LiteralPath $Path -File -Recurse -ErrorAction SilentlyContinue |
        ForEach-Object { $total += $_.Length }
    $total
}

# --- Rutas y destinos -------------------------------------------------------
$Downloads = Get-DownloadsPath

$Dest = @{
    Documentos   = Join-Path $Downloads 'Documentos'
    Imagenes     = Join-Path $Downloads 'Imágenes'
    Audio        = Join-Path $Downloads 'Audio'
    Video        = Join-Path $Downloads 'Vídeo'
    Codigo       = Join-Path $Downloads 'Código'
    Instaladores = Join-Path $Downloads 'Instaladores'
    Comprimidos  = Join-Path $Downloads 'Comprimidos'
    Torrents     = Join-Path $Downloads 'Torrents'
    Texto        = Join-Path $Downloads 'Texto'
    Grandes      = Join-Path $Downloads '_Grandes'
    Otros        = Join-Path $Downloads 'Otros'
}
$Dest.Values | ForEach-Object { if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ | Out-Null } }

# --- Extensiones por categoría ---------------------------------------------
$Map = @{
    Documentos   = @('pdf','doc','docx','xls','xlsx','ppt','pptx','odt','ods','odp','rtf')
    Imagenes     = @('jpg','jpeg','png','gif','bmp','svg','webp','tif','tiff','heic','ico','psd','ai')
    Audio        = @('mp3','aac','wav','flac','ogg','oga','m4a','opus')
    Video        = @('mp4','mkv','avi','mov','wmv','webm','m4v')
    Codigo       = @('ps1','psm1','psd1','bat','cmd','sh','py','ipynb','js','ts','tsx','json','yml','yaml','xml','html','css','scss','c','cpp','cs','java','go','rs','rb','php','sql','md')
    Instaladores = @('msi','msix','msixbundle','exe')
    Comprimidos  = @('zip','rar','7z','tar','gz','bz2','xz','iso')
    Torrents     = @('torrent')
    Texto        = @('txt','log','csv')
}

$SizeBytes = [math]::Round($SizeThresholdGB * 1GB)

# ==================== 1) CARPETAS GRANDES (solo raíz) ======================
# Solo carpetas inmediatamente dentro de Descargas
$rootDirs = Get-ChildItem -LiteralPath $Downloads -Directory

foreach ($d in $rootDirs) {
    # no mover las carpetas de destino
    if ($Dest.Values -contains $d.FullName) { continue }

    $size = Get-FolderSizeBytes -Path $d.FullName
    if ($size -ge $SizeBytes) {
        $target = Join-Path $Dest.Grandes $d.Name
        if (Test-Path $target) { $target = New-UniquePath $target }

        if ($PSCmdlet.ShouldProcess($d.FullName, ("Mover CARPETA grande (~{0:N2} GB) → {1}" -f ($size/1GB), $Dest.Grandes))) {
            Move-Item -LiteralPath $d.FullName -Destination $target
            Write-Verbose ("[Carpeta grande] {0} → {1}  (~{2:N2} GB)" -f $d.Name, $Dest.Grandes, ($size/1GB))
        }
    }
}

# ==================== 2) ARCHIVOS (solo raíz) ==============================
$rootFiles = Get-ChildItem -LiteralPath $Downloads -File

foreach ($f in $rootFiles) {
    $ext = $f.Extension.TrimStart('.').ToLower()

    # Categoría base por extensión
    $key = $Map.Keys | Where-Object { $Map[$_] -contains $ext } | Select-Object -First 1
    $destDir = if ($key) { $Dest[$key] } else { $Dest.Otros }

    $isCompressed = $Map.Comprimidos -contains $ext
    if ($f.Length -ge $SizeBytes) {
        # Archivos grandes (incluidos comprimidos grandes) → _Grandes
        $destDir = $Dest.Grandes
    } elseif ($isCompressed) {
        # Comprimidos que NO superan el umbral → Comprimidos
        $destDir = $Dest.Comprimidos
    }

    $target = Join-Path $destDir $f.Name
    if (Test-Path $target) { $target = New-UniquePath $target }

    if ($PSCmdlet.ShouldProcess($f.FullName, "Mover archivo → '$destDir'")) {
        Move-Item -LiteralPath $f.FullName -Destination $target
        Write-Verbose ("[Archivo] {0} → {1}" -f $f.Name, $destDir)
    }
}

Write-Verbose "Organización completada."
