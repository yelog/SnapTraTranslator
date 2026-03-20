# Windows Native Shell

This directory now contains the first native Windows shell scaffold for SnapTra.

Current shape:
- `SnapTra.Windows.sln` hosts a single packaged WinUI 3 project
- `src/SnapTra.Windows` contains the shell, settings, and placeholder platform interfaces
- `src/SnapTra.Windows/Assets` already contains checked-in placeholder MSIX icon assets
- `tools/GeneratePlaceholderAssets.ps1` regenerates those assets on a Windows machine when branding changes

Bootstrap scope:
- tray-first startup
- hidden shell message window
- native tray menu
- global hotkey registration
- minimal settings window
- single-project MSIX packaging

Out of scope for this milestone:
- OCR
- screen capture
- dictionary lookup
- translation
- speech
- any extra executable or helper process

Notes:
- The project files are written as a static scaffold here and still need a Windows machine for MSBuild/package verification.
- Keep future Windows work under `apps/windows` so the macOS targets stay isolated.
- Typical verification flow on Windows:
  - `msbuild ./apps/windows/src/SnapTra.Windows/SnapTra.Windows.csproj /restore /p:Configuration=Debug`
  - `msbuild ./apps/windows/src/SnapTra.Windows/SnapTra.Windows.csproj /restore /p:Configuration=Release /p:GenerateAppxPackageOnBuild=true`
