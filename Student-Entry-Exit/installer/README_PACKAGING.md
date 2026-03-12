Packaging and distribution notes

This project includes helper scripts and a simple Inno Setup template to create a Windows installer or a portable ZIP of the Flutter Windows release.

Quick steps to create a portable bundle (recommended for simple distribution):
1. Ensure `flutter` is available in PATH and you can build Windows apps: `flutter doctor`.
2. From the repo root (PowerShell), run:

   .\scripts\build_windows_release.ps1

   This runs `flutter build windows --release` and copies the release artifacts into `dist\\app`.

3. Create a portable ZIP you can hand to users:

   .\scripts\create_portable_zip.ps1

   The ZIP will be created at `dist\\Attendance-Windows.zip`.

4. (Optional) Use the Inno Setup script `installer\\AttendanceInstaller.iss` to create a standard Windows installer (.exe). Install Inno Setup, edit the `SourceDir` constant in the .iss or use the Inno GUI to point to `dist\\app`, then compile.

Firewall & Networking
- If your app listens on a TCP port (default 9000), you may need to allow it in Windows Firewall. Use the included script (run as Administrator):

  .\\scripts\\add_firewall_rule.ps1 -Port 9000

Microsoft Store / MSIX
- To publish to Microsoft Store you need to package the app as MSIX. MSIX requires:
  - An MSIX package (tools: MSIX Packaging Tool, Advanced Installer, or the MSIX CLI)
  - A Store-compatible appxmanifest and app identity
  - Code signing with a trusted certificate for submission
- Packaging for the Store is more involved. If you want, I can:
  - Create an MSIX packaging script outline and a sample appxmanifest
  - Walk through the Store submission checklist and signing steps

Notes & recommendations
- Flutter Windows builds produce a self-contained set of files (exe + DLLs + assets). Distribute the whole folder or an installer.
- For the "no-install" experience, provide a ZIP that contains the exe and run instructions; it still requires Windows to have standard runtime libraries (Windows 10/11 are fine).
- For best UX and to avoid SmartScreen warnings, sign your executable and installer with a code-signing certificate.

If you'd like, I can:
- Generate the MSIX outline and helper files to begin submission to the Microsoft Store.
- Create an automated packaging script that runs the build, zips, and (optionally) launches Inno Setup to compile the installer (you'll need Inno Setup installed locally).
- Add a small launcher/wrapper that sets up a firewall rule automatically when run (requires elevation) and then starts the app.

Tell me which of these you'd like me to add next.