# teknetv

Windows-focused build notes

### Windows portable build
- We now produce a portable Windows bundle that includes `teknetv.exe`, `flutter_windows.dll`, ICU data, plugins, native assets, and `data/flutter_assets`.
- In GitHub Actions, download the artifact named `teknetv-windows-portable` and unzip it. Run `teknetv.exe` directly from the unzipped folder.

### Windows single EXE installer
- CI also produces an NSIS installer: download the artifact `teknetv-windows-setup` and run the `teknetv-Setup-<version>.exe` file. It installs the app to `C:\Program Files\teknetv` and creates shortcuts.

### Local Windows build
1. Install Flutter (stable) and enable desktop: `flutter config --enable-windows-desktop`.
2. Fetch deps: `flutter pub get`.
3. Build: `flutter build windows --release`.
4. Run from bundle folder: `build/windows/x64/runner/Release/teknetv.exe`.
   - Ensure you run the EXE from that folder so it can load `flutter_windows.dll` and `icudtl.dat` next to it.

If you see "flutter_windows.dll not found", it means the EXE was moved without its sibling files. Always run within the Release folder, or use the portable ZIP artifact.
