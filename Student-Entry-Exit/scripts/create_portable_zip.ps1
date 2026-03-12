# Create a portable ZIP of the built Windows release found in dist\app
# Usage: .\create_portable_zip.ps1 -SourceDir dist\app -OutFile dist\Attendance-Windows.zip
param(
    [string]$SourceDir = 'dist\\app',
    [string]$OutFile = 'dist\\Attendance-Windows.zip'
)

if (!(Test-Path $SourceDir)) {
    Write-Error "Source directory not found: $SourceDir. Run build_windows_release.ps1 first."
    exit 1
}

if (Test-Path $OutFile) { Remove-Item -Force $OutFile }

Write-Output "Creating ZIP $OutFile from $SourceDir"
Compress-Archive -Path (Join-Path $SourceDir '*') -DestinationPath $OutFile -Force
Write-Output "ZIP created: $OutFile"