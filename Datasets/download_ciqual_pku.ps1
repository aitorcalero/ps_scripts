<#
==============================================================
 Script: download_amino_dataset.ps1
 Autor: AminoGPT
 Descripción:
   Descarga y organiza datasets nutricionales (CIQUAL, USDA, FAO,
   WHO, EFSA) y guías PKU en un paquete ZIP con verificación SHA-256.
==============================================================
#>

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Carpeta base
$basePath = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$destRoot = Join-Path $basePath "amino_project_dataset"
$zipPath  = Join-Path $basePath "amino_project_dataset_plus.zip"
$hashReport = Join-Path $destRoot "SHA256_CHECKSUMS.txt"

# Crear carpetas principales
$folders = @("CIQUAL_2020", "USDA_FoodDataCentral", "FAO_INFOODS", "WHO", "EFSA_OpenFoodTox", "PKU_Guidelines")
foreach ($f in $folders) {
    $path = Join-Path $destRoot $f
    if (-not (Test-Path $path)) { New-Item -ItemType Directory -Force -Path $path | Out-Null }
}

# Función auxiliar de descarga robusta (HttpClient)
Add-Type -AssemblyName System.Net.Http
$handler = New-Object System.Net.Http.HttpClientHandler
$handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
$client = New-Object System.Net.Http.HttpClient($handler)
$client.DefaultRequestHeaders.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
$client.DefaultRequestHeaders.Add("Accept", "*/*")

function Download-File($url, $outputPath) {
    try {
        $response = $client.GetAsync($url).Result
        if ($response.IsSuccessStatusCode) {
            $bytes = $response.Content.ReadAsByteArrayAsync().Result
            [System.IO.File]::WriteAllBytes($outputPath, $bytes)
            Write-Host "✔️  Descargado: $([System.IO.Path]::GetFileName($outputPath))"
        } else {
            Write-Warning "⚠️  HTTP $($response.StatusCode) → $url"
        }
    } catch {
        Write-Warning "⚠️  Error al descargar $url"
    }
}

Write-Host "`n=== DESCARGANDO FUENTES NUTRICIONALES ===`n" -ForegroundColor Cyan

# --- CIQUAL 2020 ---
Download-File "https://ciqual.anses.fr/cms/sites/default/files/inline-files/Table%20Ciqual%202020_doc_XML_ENG_2020%2007%2007.pdf" "$destRoot\CIQUAL_2020\Table_Ciqual_2020_XML_ENG.pdf"
Download-File "https://ciqual.anses.fr/cms/sites/default/files/inline-files/Table%20Ciqual%202020_doc_XML_FR_2020%2007%2007.pdf" "$destRoot\CIQUAL_2020\Table_Ciqual_2020_XML_FR.pdf"

# --- USDA FoodData Central ---
Download-File "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_foundation_food_csv_2025-04-04.zip" "$destRoot\USDA_FoodDataCentral\FoundationFoods2025.zip"
Download-File "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_food_nutrient_csv_2025-04-04.zip" "$destRoot\USDA_FoodDataCentral\FoodNutrient2025.zip"

# --- FAO INFOODS ---
Download-File "https://www.fao.org/3/ca8864en/ca8864en.zip" "$destRoot\FAO_INFOODS\INFOODS_Biodiversity_V4.0.zip"

# --- WHO Nutrient Requirements 2023 ---
Download-File "https://apps.who.int/iris/rest/bitstreams/1592418/retrieve" "$destRoot\WHO\WHO_Nutrient_Requirements_2023.pdf"

# --- EFSA OpenFoodTox ---
Download-File "https://zenodo.org/records/8205913/files/EFSA_OpenFoodTox_2023.zip?download=1" "$destRoot\EFSA_OpenFoodTox\OpenFoodTox_Database.zip"

# --- PKU Guidelines ---
Download-File "https://www.spdm.org.pt/media/1373/pku-guidelines_2017.pdf" "$destRoot\PKU_Guidelines\PKU_Guidelines_2017.pdf"
Download-File "https://pmc.ncbi.nlm.nih.gov/articles/PMC5639803/pdf/main.pdf" "$destRoot\PKU_Guidelines\PKU_European_Guidelines_2017_PMC.pdf"

# --- Crear README generales ---
"Datos descargados automáticamente el $(Get-Date -Format 'dd/MM/yyyy HH:mm') con AminoGPT." | Out-File -FilePath (Join-Path $destRoot "README.txt") -Encoding UTF8

# --- Calcular hashes SHA256 ---
Write-Host "`nCalculando hashes SHA-256..." -ForegroundColor Yellow
if (Test-Path $hashReport) { Remove-Item $hashReport -Force }
Get-ChildItem -Path $destRoot -Recurse -File | ForEach-Object {
    $hash = Get-FileHash -Algorithm SHA256 -Path $_.FullName
    "$($hash.Hash)  $($_.FullName.Replace($destRoot, ''))" | Out-File -Append -FilePath $hashReport -Encoding UTF8
}
Write-Host "✔️  Archivo de verificación generado: $hashReport" -ForegroundColor Green

# --- Crear ZIP consolidado ---
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path "$destRoot\*" -DestinationPath $zipPath -Force

Write-Host "`n✅ Paquete científico creado:" -ForegroundColor Green
Write-Host "   $zipPath"
Start-Process $basePath
Write-Host "`n✨ Descarga completa y verificada. Dataset listo para integración." -ForegroundColor Cyan
