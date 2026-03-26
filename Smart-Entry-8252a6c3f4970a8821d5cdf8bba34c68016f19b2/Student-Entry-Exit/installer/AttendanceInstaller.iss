; Inno Setup script for packaging the Flutter Windows release into an installer
; Install Inno Setup (https://jrsoftware.org/isinfo.php) and compile this .iss to produce a single installer .exe
; Update AppName, DefaultDirName, and SourceDir as needed before compiling.

[Setup]
AppName=Attendance Dashboard
AppVersion=1.0
DefaultDirName={pf}\AttendanceDashboard
DefaultGroupName=Attendance Dashboard
Compression=lzma
SolidCompression=yes
OutputBaseFilename=AttendanceInstaller

; point this to the directory containing the built exe and dlls (dist\app produced by scripts/build_windows_release.ps1)
#define SourceDir "..\\dist\\app"

[Files]
; copy everything from SourceDir
Source: "{#SourceDir}\\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Attendance Dashboard"; Filename: "{app}\\Attendance.exe"
Name: "{commondesktop}\Attendance Dashboard"; Filename: "{app}\\Attendance.exe"; Tasks: desktopicon

[Tasks]
Name: desktopicon; Description: "Create a &desktop icon"; GroupDescription: "Additional icons:"; Flags: unchecked

[Run]
Filename: "{app}\\Attendance.exe"; Description: "Launch Attendance Dashboard"; Flags: nowait postinstall skipifsilent

; Notes:
; - Replace Attendance.exe with the actual runner exe name created by Flutter (usually the project name or runner.exe). 
; - Use a code signing certificate for the installer to avoid SmartScreen warnings.
; - This installer can be used for distribution; for Microsoft Store packaging you need an MSIX package instead.
