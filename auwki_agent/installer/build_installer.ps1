param(
  [string]$Version = "1.2.0",
  [string]$BuildRoot = "C:\auwki_build"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$srcDir = Join-Path $BuildRoot "src_$stamp"
$stageDir = Join-Path $BuildRoot "installer_stage_$stamp"
$flutterProject = Join-Path $srcDir "auwki_agent"

Write-Host "== AUWKI Agent Installer Build =="
Write-Host "Version : $Version"
Write-Host "Repo    : $repoRoot"
Write-Host "Build   : $srcDir"

# 1. 复制源码到纯英文路径（中文用户名会触发 MSBuild 编码 bug）
if (-not (Test-Path $BuildRoot)) {
  New-Item -ItemType Directory -Path $BuildRoot -Force | Out-Null
}
New-Item -ItemType Directory -Path $srcDir -Force | Out-Null
robocopy $repoRoot $srcDir /E /NFL /NDL /NJH /NJS /NC /NS `
  /XD .git build dist .dart_tool .idea .vscode .venv venv node_modules `
      ephemeral .plugin_symlinks `
  /XF *.zip *.7z *.exe "*.log"
if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit code $LASTEXITCODE" }

# 2. 构建 Windows Release
Write-Host "`n[1/4] flutter build windows --release ..."
Push-Location $flutterProject
try {
  # webview_windows 插件需要 nuget.exe（固定 5.10.0 + SHA256）。
  # 网络不稳时从本地缓存预置，避免下载损坏导致 integrity check 失败。
  $nugetCache = "C:\auwki_build\nuget-5.10.0.exe"
  if (Test-Path $nugetCache) {
    $nugetDest = Join-Path $flutterProject "build\windows\x64\nuget.exe"
    New-Item -ItemType Directory -Path (Split-Path $nugetDest) -Force | Out-Null
    Copy-Item $nugetCache $nugetDest -Force
    Write-Host "Pre-seeded nuget.exe from local cache."
  }
  flutter build windows --release
  if ($LASTEXITCODE -ne 0) { throw "flutter build failed with exit code $LASTEXITCODE" }
} finally {
  Pop-Location
}

# 3. 整理安装目录（stage）
$releaseDir = Join-Path $flutterProject "build\windows\x64\runner\Release"
if (-not (Test-Path $releaseDir)) {
  throw "Release output not found: $releaseDir"
}
Write-Host "[2/4] Staging files ..."
New-Item -ItemType Directory -Path $stageDir -Force | Out-Null
robocopy $releaseDir $stageDir /E /NFL /NDL /NJH /NJS /NC /NS
if ($LASTEXITCODE -ge 8) { throw "staging failed with exit code $LASTEXITCODE" }
$readme = Join-Path $repoRoot "dist\使用说明.txt"
if (Test-Path $readme) {
  Copy-Item $readme (Join-Path $stageDir "使用说明.txt") -Force
}

# 4. 查找 Inno Setup
Write-Host "[3/4] Locating Inno Setup ..."
$iscc = $null
if ($env:INNO_SETUP_HOME) {
  $candidate = Join-Path $env:INNO_SETUP_HOME "ISCC.exe"
  if (Test-Path $candidate) { $iscc = $candidate }
}
if (-not $iscc) {
  $candidates = @(
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe",
    (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe"),
    (Join-Path $BuildRoot "InnoSetup6\ISCC.exe")
  )
  foreach ($c in $candidates) {
    if (Test-Path $c) { $iscc = $c; break }
  }
}
if (-not $iscc) {
  Write-Host "Inno Setup not found. Installing via winget ..."
  winget install -e --id JRSoftware.InnoSetup `
    --accept-package-agreements --accept-source-agreements
  foreach ($c in $candidates) {
    if (Test-Path $c) { $iscc = $c; break }
  }
}
if (-not $iscc) {
  throw "Inno Setup 6 (ISCC.exe) not found. Please install it, then re-run this script."
}

# 5. 编译安装程序
Write-Host "[4/4] Compiling installer ..."
$iss = Join-Path $scriptDir "AUWKI-Agent.iss"
& $iscc $iss /DStageDir="$stageDir" /DAppVersion="$Version"
if ($LASTEXITCODE -ne 0) { throw "ISCC failed with exit code $LASTEXITCODE" }

$outDir = Join-Path $repoRoot "dist\installer"
Write-Host "`nDone! Installer output:"
Get-ChildItem $outDir -Filter "AUWKI-Agent-Setup-*.exe" | ForEach-Object {
  Write-Host "  $($_.FullName)  ($([math]::Round($_.Length / 1MB, 1)) MB)"
}
