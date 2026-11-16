@echo off
setlocal enabledelayedexpansion
REM ============================================================
REM  Animax - one-click Windows .exe build
REM
REM  Requirements (one-time setup):
REM   1. Flutter SDK (stable)  https://docs.flutter.dev/get-started/install/windows
REM   2. Visual Studio 2022 Community with the
REM      "Desktop development with C++" workload (includes MSVC + Windows SDK)
REM   3. Git for Windows
REM  Verify with: flutter doctor  (no red crosses in the two rows above)
REM ============================================================

where flutter >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Flutter was not found in PATH.
  echo         Install the Flutter SDK, reopen this terminal, and try again.
  pause
  exit /b 1
)

REM Read the app version from pubspec.yaml (e.g. 1.6.1+8 -^> 1.6.1)
for /f "tokens=2" %%v in ('findstr /b "version:" pubspec.yaml') do set RAWVER=%%v
for /f "delims=+" %%a in ("!RAWVER!") do set VER=%%a

echo.
echo === [1/3] Resolving dependencies ===
call flutter pub get
if errorlevel 1 goto :fail

echo.
echo === [2/3] Building Windows release (this takes a few minutes) ===
call flutter build windows --release
if errorlevel 1 goto :fail

set OUT=build\windows\x64\runner\Release
set DIST=Animax-!VER!-windows-x64

echo.
echo === [3/3] Packaging into %DIST% ===
if exist "%DIST%" rmdir /s /q "%DIST%"
xcopy "%OUT%" "%DIST%\" /e /i /q
if errorlevel 1 goto :fail

powershell -NoProfile -Command "Compress-Archive -Path '%DIST%\*' -DestinationPath 'Animax-!VER!-windows-x64.zip' -Force"

echo.
echo ==================== DONE ====================
echo   Executable : %DIST%\animax.exe
echo   Zip file   : Animax-!VER!-windows-x64.zip
echo.
echo   Share the WHOLE folder (or the zip), not just
echo   the exe: it needs the DLLs and the data\ dir.
echo ==============================================
echo.
pause
exit /b 0

:fail
echo.
echo [ERROR] The build failed - read the messages above.
echo         Common causes: Visual Studio C++ workload missing
echo         (run "flutter doctor" to check).
echo.
pause
exit /b 1
