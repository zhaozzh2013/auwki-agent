# AUWKI Agent - helper build script (no Flutter install required)
#
# What it does:
#   1. Uses the local source if present, otherwise downloads it from GitHub.
#   2. Downloads a PORTABLE Flutter SDK (into a local tools folder, not installed).
#   3. Checks for Visual Studio C++ toolchain (MSVC + Windows SDK).
#   4. Builds the Windows release in a pure-ASCII path (avoids Chinese path bugs).
#   5. Packages the result into AUWKI-Agent-windows-x64.zip.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File build_for_friend.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File build_for_friend.ps1 -InstallBuildTools
#
# Options:
#   -FlutterVersion 3.44.8   Pin a specific Flutter version.
#   -InstallBuildTools       Auto-install Visual Studio Build Tools (C++ workload) if missing.
#   -OutputDir "D:\out"      Where to put the final zip (default: repo/dist/friend_build).

param(
  [string]$FlutterVersion = "3.44.8",
  [switch]$InstallBuildTools,
  [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

function Test-Ascii([string]$s) {
  return $s -match '^[\x00-\x7F]+$'
}

function New-AsciiDir([string]$path) {
  try {
    New-Item -ItemType Directory -Path $path -Force -ErrorAction Stop | Out-Null
    return $true
  } catch {
    return $false
  }
}

function Get-AsciiRoot([string]$name) {
  $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $candidates = @(
    (Join-Path $env:TEMP "$name`_$stamp"),
    "C:\$name`_$stamp",
    (Join-Path $repoRoot $name)
  )
  foreach ($c in $candidates) {
    if ((Test-Ascii $c) -and (New-AsciiDir $c)) {
      return $c
    }
  }
  return $null
}

function Download-File([string]$url, [string]$dest) {
  if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
    & curl.exe -L --retry 3 --connect-timeout 30 -o $dest $url
    return ($LASTEXITCODE -eq 0) -and (Test-Path $dest) -and ((Get-Item $dest).Length -gt 1024)
  }
  try {
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    return (Test-Path $dest) -and ((Get-Item $dest).Length -gt 1024)
  } catch {
    return $false
  }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

Write-Host "== AUWKI Agent helper build =="
Write-Host "Repo root : $repoRoot"

# ---------- 1. Source ----------
$flutterProject = Join-Path $repoRoot "auwki_agent"
if (-not (Test-Path (Join-Path $flutterProject "pubspec.yaml"))) {
  Write-Host "Local source not found. Downloading source from GitHub..."
  $srcTmp = Join-Path $env:TEMP "auwki_agent_source"
  if (Test-Path $srcTmp) {
    Remove-Item -LiteralPath $srcTmp -Recurse -Force
  }
  if (Get-Command git -ErrorAction SilentlyContinue) {
    & git clone --depth 1 https://github.com/zhaozzh2013/auwki-agent.git $srcTmp
    if ($LASTEXITCODE -ne 0) { throw "git clone failed. Please send the source folder next to this script." }
    $repoRoot = $srcTmp
  } else {
    $zipPath = Join-Path $env:TEMP "auwki_agent_source.zip"
    $zipUrl = "https://github.com/zhaozzh2013/auwki-agent/archive/refs/heads/main.zip"
    if (-not (Download-File $zipUrl $zipPath)) {
      throw "Source download failed. Please send the source folder next to this script."
    }
    Expand-Archive -Path $zipPath -DestinationPath $srcTmp -Force
    $repoRoot = (Get-ChildItem $srcTmp -Directory | Select-Object -First 1).FullName
  }
  $flutterProject = Join-Path $repoRoot "auwki_agent"
  if (-not (Test-Path (Join-Path $flutterProject "pubspec.yaml"))) {
    throw "Source does not contain auwki_agent/pubspec.yaml"
  }
}

# ---------- 2. Portable Flutter (no install) ----------
$flutterBat = $null
if (Get-Command flutter -ErrorAction SilentlyContinue) {
  Write-Host "System Flutter found, using it: $((Get-Command flutter).Source)"
  $flutterBat = (Get-Command flutter).Source
} else {
  Write-Host "No Flutter installed. Preparing a PORTABLE Flutter SDK (first run downloads ~1GB)..."
  $toolsRoot = Get-AsciiRoot "auwki_flutter_tools"
  if (-not $toolsRoot) {
    throw "Could not find an ASCII-only writable path. Put this project in a pure-English path (e.g. D:\build\auwki) and retry."
  }
  $flutterRoot = Join-Path $toolsRoot "flutter_$FlutterVersion"
  $flutterBat = Join-Path $flutterRoot "flutter\bin\flutter.bat"
  if (-not (Test-Path $flutterBat)) {
    $zipPath = Join-Path $toolsRoot "flutter_$FlutterVersion.zip"
    if (-not (Test-Path $zipPath)) {
      $urls = @(
        "https://storage.flutter-io.cn/flutter_infra_release/releases/stable/windows/flutter_windows_$FlutterVersion-stable.zip",
        "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_$FlutterVersion-stable.zip"
      )
      $ok = $false
      foreach ($u in $urls) {
        Write-Host "Downloading $u"
        if (Download-File $u $zipPath) { $ok = $true; break }
      }
      if (-not $ok) {
        throw "Failed to download the portable Flutter SDK. Please check your network and retry."
      }
    }
    Write-Host "Extracting Flutter SDK..."
    Expand-Archive -Path $zipPath -DestinationPath $flutterRoot -Force
  }
  Write-Host "Portable Flutter ready: $flutterBat"
}

# China-friendly pub/storage mirrors (only set when not already configured).
if (-not $env:PUB_HOSTED_URL) { $env:PUB_HOSTED_URL = "https://pub.flutter-io.cn" }
if (-not $env:FLUTTER_STORAGE_BASE_URL) { $env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn" }

# ---------- 3. Visual Studio C++ toolchain ----------
$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
$vsPath = $null
if (Test-Path $vswhere) {
  $vsPath = & $vswhere -latest -products * `
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    -requires Microsoft.VisualStudio.Component.Windows10SDK `
    -property installationPath
}
if (-not $vsPath) {
  Write-Host ""
  Write-Host "Visual Studio C++ toolchain (MSVC + Windows SDK) was not found."
  if ($InstallBuildTools) {
    Write-Host "Installing Visual Studio Build Tools with the C++ workload. This is large and may take a long time."
    & winget install -e --id Microsoft.VisualStudio.2022.BuildTools `
      --override "--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --quiet --norestart" `
      --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
      throw "Build Tools install failed. Please install it manually and re-run."
    }
    $vsPath = & $vswhere -latest -products * `
      -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
      -requires Microsoft.VisualStudio.Component.Windows10SDK `
      -property installationPath
    if (-not $vsPath) {
      throw "Build Tools installed, but the C++ workload is still missing. Re-run with: -InstallBuildTools  (or install it manually)."
    }
  } else {
    Write-Host ""
    Write-Host "How to fix (choose one):"
    Write-Host "  1) Re-run this script with the -InstallBuildTools switch to auto-install the free Build Tools."
    Write-Host "  2) Install 'Visual Studio 2022 Build Tools' manually and select the workload:"
    Write-Host "     Desktop development with C++  (or workload VCTools)"
    Write-Host "     https://visualstudio.microsoft.com/downloads/#build-tools-for-visual-studio-2022"
    throw "Visual Studio C++ toolchain is required to build the Windows app."
  }
}
Write-Host "Visual Studio C++ toolchain OK: $vsPath"

# ---------- 4. ASCII build root ----------
$buildRoot = Get-AsciiRoot "auwki_build"
if (-not $buildRoot) {
  throw "Could not find an ASCII-only writable build path. Put this project in a pure-English path (e.g. D:\build\auwki) and retry."
}
$srcDir = Join-Path $buildRoot "src_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-AsciiDir $srcDir | Out-Null

Write-Host "Copying source to ASCII path: $srcDir"
robocopy $repoRoot $srcDir /E /NFL /NDL /NJH /NJS /NC /NS `
  /XD .git build dist .dart_tool .idea .vscode .venv venv node_modules `
      ephemeral .plugin_symlinks `
  /XF *.zip *.7z *.exe "*.log"
if ($LASTEXITCODE -ge 8) {
  throw "Source copy failed with robocopy exit code $LASTEXITCODE"
}

# ---------- 5. Build ----------
Write-Host "Building Windows release (this takes several minutes on first run)..."
Push-Location (Join-Path $srcDir "auwki_agent")
try {
  & $flutterBat build windows --release
  if ($LASTEXITCODE -ne 0) {
    throw "flutter build failed with exit code $LASTEXITCODE"
  }
} finally {
  Pop-Location
}

# ---------- 6. Package ----------
$releaseDir = Join-Path $srcDir "auwki_agent\build\windows\x64\runner\Release"
if (-not (Test-Path $releaseDir)) {
  throw "Release output not found: $releaseDir"
}
if ($OutputDir -eq "") {
  $OutputDir = Join-Path $repoRoot "dist\friend_build"
}
New-AsciiDir $OutputDir | Out-Null
$zipPath = Join-Path $OutputDir "AUWKI-Agent-windows-x64.zip"
if (Test-Path $zipPath) {
  Remove-Item -LiteralPath $zipPath -Force
}
Write-Host "Packaging zip..."
Compress-Archive -Path "$releaseDir\*" -DestinationPath $zipPath -CompressionLevel Optimal

Write-Host ""
Write-Host "================================"
Write-Host "BUILD OK"
Write-Host "Output: $zipPath"
Write-Host "Size  : $([math]::Round((Get-Item $zipPath).Length / 1MB, 1)) MB"
Write-Host "================================"
