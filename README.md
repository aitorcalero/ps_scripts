# PowerShell Scripts Repository

This repository contains a collection of PowerShell scripts for system administration, AI integration, workspace management, and various automation tasks.

## 📂 Directory Structure

### 🤖 `AI_Tools/`
Scripts for setting up and interacting with AI models (Ollama, OpenAI, Gemini, Manus).
- **`Setup-AIStack.ps1`**: Main setup script for installing Ollama, prompting for API keys, and automatically recommending local models based on your hardware.
- **`AI_PowerShell*.ps1` / `AI_Cloud_PowerShell.ps1`**: Various versions/wrappers of AI CLI integrations.
- **`ConfigurarTareaRAG.ps1` & `install-gpt.ps1`**: Additional AI utility scripts.

### ⚙️ `System_Tuning/`
Tools for optimizing workstation performance and managing system startups.
- **`Optimize-Workstation.ps1`**: General performance tuning.
- **`Disable-Startup-Extras.ps1` & `LimpiarArranque.ps1`**: Startup cleaners.
- **`Invoke-StaggeredStartupFromExisting.ps1`**: Delays the launch of startup applications to improve boot times.
- **`Audit-ScheduledTasks.ps1`**: Audits and reports on Windows scheduled tasks.

### 🧹 `Workspace_Management/`
Scripts to keep the local filesystem clean and organized.
- **`Organizar-Escritorio.ps1` / `OrganizarEscritorio.ps1`**: Cleans up the Desktop by categorizing files.
- **`Organizar-Descargas.ps1`**: Automatically sorts the Downloads folder.

### 🛠️ `Utilities/`
Automation helpers and system fixes.
- **`launcher.ps1` & `Log-On.ps1`**: Login scripts and generic app launchers.
- **`sudo.ps1`**: Easy elevation wrapper for PowerShell commands (`sudo <cmd>`).
- **`Fix-PythonEnvs.ps1`**: Fixes corrupted Python virtual environments (especially within OneDrive).
- **`Fix-Duet-AppleUSB.ps1`**: Fixes conflicts between Duet Display and Apple USB drivers.
- **`Convert-EmlToTxt.ps1`**: Extracts text from `.eml` files.
- **`AutoHotKey.ps1`**: AHK integration or deployment.

### 📦 `Datasets/`
Scripts for downloading specific datasets for testing or AI training.
- **`download_amino_dataset_flat.ps1`**
- **`download_ciqual_pku.ps1`**

## 🚀 Getting Started
Most of these scripts require PowerShell 7+ (`pwsh`). 
To run them, you may need to bypass the execution policy:
```powershell
pwsh -ExecutionPolicy Bypass -File <script_name>.ps1
```

*Note: Proceed with caution when running system-modifying scripts.*
