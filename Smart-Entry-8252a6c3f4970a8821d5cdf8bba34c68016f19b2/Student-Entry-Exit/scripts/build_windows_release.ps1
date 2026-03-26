# Build a release Windows bundle for the Flutter app and collect artifacts into dist\app
# Run this from the repository root in PowerShell (requires flutter in PATH)

param(
    [string]$Configuration = 'release'
)

# 1) Build Flutter Windows release
Write-Output "Running: flutter build windows --$Configuration"
flutter build windows --$Configuration

# 2) Locate build output (Flutter places native runner and files under build\windows\runner\$Configuration)
$runnerDir = Join-Path -Path "build\windows\runner" -ChildPath $Configuration
if (!(Test-Path $runnerDir)) {
    Write-Error "Cannot find built runner at $runnerDir. Build may have failed."
    exit 1
}

# 3) Copy release artifacts to dist\app
$dist = Join-Path -Path "dist" -ChildPath "app"
if (Test-Path $dist) { Remove-Item -Recurse -Force $dist }
New-Item -ItemType Directory -Path $dist | Out-Null

Write-Output "Copying files from $runnerDir to $dist"
Get-ChildItem -Path $runnerDir -File | ForEach-Object { Copy-Item -Path $_.FullName -Destination $dist }
# copy resources directory if exists
$resources = Join-Path -Path $runnerDir -ChildPath 'data'
if (Test-Path $resources) { Copy-Item -Path $resources -Destination $dist -Recurse }

Write-Output "Release artifacts are in: $dist"
Write-Output "You can distribute the contents of $dist (exe + dlls + data). To make a single ZIP: run the create_portable_zip.ps1 script."