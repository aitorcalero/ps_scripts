<#
Organizar-Descargas.ps1 (v1.2)
- Comprimidos: a 'Comprimidos' (si superan umbral => '_Grandes').
- Archivos grandes: a '_Grandes'.
- Carpetas grandes (recursivo con -Recurse): a '_Grandes\Carpetas'.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [double] $SizeThresholdGB = 1.0,
    [double] $FolderSizeThresholdGB,
    [switch] $Recurse
)
if (-not $PSBoundParameters.ContainsKey('FolderSizeThresholdGB')) {
    $FolderSizeThresholdGB = $SizeThresholdGB
}

function Get-DownloadsPath {
    try { $p = [Environment]::GetFolderPath('Downloads'); if ($p -and (Test-Path $p)) { return $p } } catch {}
    $fb = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'
    if (Test-Path $fb) { return $fb }
    throw "No se pudo resolver la ruta de Descargas."
}
function New-UniquePath([Parameter(Mandatory)][string]$TargetPath) {
    if (-not (Test-Path $TargetPath)) { return $TargetPath }
    $dir = Split-Path $TargetPath -Parent
    $base = [IO.Path]::GetFileNameWithoutExtension($TargetPath)
    $ext = [IO.Path]::GetExtension($TargetPath)
    $i=1; do { $cand = Join-Path $dir ("{0} ({1}){2}" -f $base,$i,$ext); $i++ } while (Test-Path $cand)
    $cand
}
function Is-Under([string]$Path,[string]$Ancestor) {
    $p=[IO.Path]::GetFullPath($Path); $a=[IO.Path]::GetFullPath($Ancestor)
    return $p.StartsWith($a,[StringComparison]::OrdinalIgnoreCase)
}
function Get-FolderSizeBytes([Parameter(Mandatory)][string]$Path) {
    $total = 0L
    Get-ChildItem -LiteralPath $Path -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $total += $_.Length }
    $total
}

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
$Dest['GrandesCarpetas'] = Join-Path $Dest.Grandes 'Carpetas'
$Dest.Values | ForEach-Object { if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ | Out-Null } }

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

$SizeBytes       = [math]::Round($SizeThresholdGB * 1GB)
$FolderSizeBytes = [math]::Round($FolderSizeThresholdGB * 1GB)

# -------- ARCHIVOS --------
$gciFileParams = @{ Path=$Downloads; File=$true }
if ($Recurse) { $gciFileParams['Recurse']=$true } else { $gciFileParams['Depth']=0 }

$files = Get-ChildItem @gciFileParams | Where-Object {
    $parent = $_.DirectoryName
    -not ($Dest.Values | Where-Object { Is-Under $parent $_ })
}

foreach ($f in $files) {
    $ext = $f.Extension.TrimStart('.').ToLower()
    $key = $Map.Keys | Where-Object { $Map[$_] -contains $ext } | Select-Object -First 1
    $destDir = $key ? $Dest[$key] : $Dest.Otros

    $isCompressed = $Map.Comprimidos -contains $ext
    if ($f.Length -ge $SizeBytes) {
        # Comprimidos grandes y no comprimidos grandes -> _Grandes
        $destDir = $Dest.Grandes
    } elseif ($isCompressed) {
        # Comprimidos pequeños/medios -> Comprimidos
        $destDir = $Dest.Comprimidos
    }

    $target = Join-Path $destDir $f.Name
    if (Test-Path $target) { $target = New-UniquePath $target }
    if ($PSCmdlet.ShouldProcess($f.FullName,"Mover a '$destDir'")) {
        Move-Item -LiteralPath $f.FullName -Destination $target
    }
}

# -------- CARPETAS (RECURRENTE) --------
# Incluye subcarpetas si -Recurse; ordena por profundidad descendente para evitar conflictos.
$gciDirParams = @{ Path=$Downloads; Directory=$true }
if ($Recurse) { $gciDirParams['Recurse']=$true } else { $gciDirParams['Depth']=0 }

$destRoots = $Dest.Values
$dirs = Get-ChildItem @gciDirParams | Where-Object {
    $p = $_.FullName
    # excluir destinos y cualquier carpeta situada dentro de un destino
    -not ($destRoots | Where-Object { $p -eq $_ -or Is-Under $p $_ })
} | Sort-Object { $_.FullName.Split([IO.Path]::DirectorySeparatorChar).Count } -Descending

foreach ($d in $dirs) {
    $size = Get-FolderSizeBytes -Path $d.FullName
    if ($size -ge $FolderSizeBytes) {
        $destDir = $Dest.GrandesCarpetas
        $target  = Join-Path $destDir $d.Name
        if (Test-Path $target) { $target = New-UniquePath $target }
        # No intentes mover una carpeta dentro de sí misma o de un descendiente (ya excluido arriba)
        if ($PSCmdlet.ShouldProcess($d.FullName,"Mover carpeta grande (~{0:N2} GB) a '$destDir'" -f ($size/1GB))) {
            Move-Item -LiteralPath $d.FullName -Destination $target
        }
    }
}

Write-Verbose "Organización completada."
