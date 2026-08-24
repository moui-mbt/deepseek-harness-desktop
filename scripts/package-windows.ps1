<#
.SYNOPSIS
  Package Windows Skia build into portable zip and optional installer.

.DESCRIPTION
  Builds windows_skia native package and bundles the exe into dist/windows.
  On Windows runners with Inno Setup (iscc) it also builds an installer.

.PARAMETER Package
  MoonBit package path (default windows_skia)

.PARAMETER AppName
  Application display name

.PARAMETER Version
  SemVer version

.PARAMETER BuildVersion
  Build number

.PARAMETER Release
  Build with --release

.PARAMETER NoBuild
  Skip moon build
#>
[CmdletBinding()]
param(
  [string]$Package = "windows_skia",
  [string]$AppName = "DSH Desktop",
  [string]$Version = "0.1.0",
  [string]$BuildVersion = "1",
  [switch]$Release,
  [switch]$NoBuild
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..")).Path
Push-Location $repoRoot
try {
  $leaf = Split-Path -Leaf $Package
  $profile = if ($Release) { "release" } else { "debug" }
  $exePath = Join-Path $repoRoot "_build/native/$profile/build/$Package/$leaf.exe"

  if (-not $NoBuild) {
    Write-Host "==> Building $Package ($profile)"
    if ($Release) {
      & moon build $Package --target native --release
    } else {
      & moon build $Package --target native
    }
    if ($LASTEXITCODE -ne 0) { throw "moon build failed with $LASTEXITCODE" }
  }

  if (-not (Test-Path -LiteralPath $exePath)) {
    throw "Built executable not found: $exePath"
  }

  $distDir = Join-Path $repoRoot "dist/windows"
  $portableDirName = "$AppName-windows-x64"
  # Sanitize for filesystem (allow spaces but be safe)
  $portableDir = Join-Path $distDir $portableDirName
  if (Test-Path -LiteralPath $portableDir) {
    Remove-Item -LiteralPath $portableDir -Recurse -Force
  }
  New-Item -ItemType Directory -Path $portableDir -Force | Out-Null

  $exeDest = Join-Path $portableDir "dsh-desktop.exe"
  Copy-Item -LiteralPath $exePath -Destination $exeDest

  # run.cmd wrapper for double-click
  $runCmd = @(
    "@echo off",
    "setlocal",
    "pushd `"%~dp0`"",
    "`"dsh-desktop.exe`" %*",
    "popd"
  )
  Set-Content -LiteralPath (Join-Path $portableDir "run.cmd") -Value $runCmd -Encoding ASCII

  @"
$AppName $Version ($BuildVersion)
Windows x64 portable build

Run:
  dsh-desktop.exe
or double-click run.cmd

Requirements:
  - WebView2 Evergreen Runtime (https://developer.microsoft.com/microsoft-edge/webview2/)
  - Windows 10 1903+

Built with MoonBit + MoUI Skia (raster).
"@ | Set-Content -LiteralPath (Join-Path $portableDir "README.txt") -Encoding UTF8

  if (Test-Path -LiteralPath (Join-Path $repoRoot "README.md")) {
    Copy-Item -LiteralPath (Join-Path $repoRoot "README.md") -Destination $portableDir -ErrorAction SilentlyContinue
  }
  if (Test-Path -LiteralPath (Join-Path $repoRoot "LICENSE")) {
    Copy-Item -LiteralPath (Join-Path $repoRoot "LICENSE") -Destination $portableDir -ErrorAction SilentlyContinue
  }

  Write-Host "==> Wrote $portableDir"

  # Zip portable
  $zipName = "DSH-Desktop-$Version-windows-x64.zip"
  $zipPath = Join-Path $repoRoot "dist/$zipName"
  if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
  Write-Host "==> Creating ZIP $zipPath"
  if (Get-Command Compress-Archive -ErrorAction SilentlyContinue) {
    Compress-Archive -Path "$portableDir/*" -DestinationPath $zipPath -Force
  } else {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($portableDir, $zipPath)
  }
  Write-Host "==> ZIP ready: $zipPath ($([math]::Round((Get-Item $zipPath).Length / 1MB,1)) MB)"

  # Inno Setup installer if iscc available
  $iscc = Get-Command iscc -ErrorAction SilentlyContinue
  if (-not $iscc) {
    $isccPaths = @(
      "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
      "${env:ProgramFiles}\Inno Setup 6\ISCC.exe"
    )
    foreach ($p in $isccPaths) {
      if (Test-Path -LiteralPath $p) { $iscc = Get-Item $p; break }
    }
  }
  if ($iscc) {
    Write-Host "==> Building Inno Setup installer with $($iscc.Source)"
    $issPath = Join-Path $env:TEMP "dsh-desktop-installer.iss"
    $issContent = @"
[Setup]
AppName=$AppName
AppVersion=$Version
AppPublisher=MoUI
DefaultDirName={autopf}\$AppName
DefaultGroupName=$AppName
OutputDir=$($repoRoot -replace '\\','\\')\dist
OutputBaseFilename=DSH-Desktop-$Version-windows-x64-setup
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64
SetupIconFile=

[Files]
Source: "$($portableDir -replace '\\','\\')\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\$AppName"; Filename: "{app}\dsh-desktop.exe"
Name: "{commondesktop}\$AppName"; Filename: "{app}\dsh-desktop.exe"; Tasks: desktopicon
[Tasks]
Name: "desktopicon"; Description: "Create a &desktop icon"; GroupDescription: "Additional icons:"
[Run]
Filename: "{app}\dsh-desktop.exe"; Description: "Launch $AppName"; Flags: nowait postinstall skipifsilent
"@
    Set-Content -LiteralPath $issPath -Value $issContent -Encoding UTF8
    & $iscc.Source $issPath
    if ($LASTEXITCODE -eq 0) {
      Write-Host "==> Installer ready in dist/"
    } else {
      Write-Host "iscc failed with $LASTEXITCODE, skipping installer" -ForegroundColor Yellow
    }
  } else {
    Write-Host "Inno Setup (iscc) not found, skipping installer (zip is available)" -ForegroundColor Yellow
  }

  Write-Host "==> Windows packaging complete"
  Write-Host "    Portable: $portableDir"
  Write-Host "    ZIP: $zipPath"
}
finally {
  Pop-Location
}
