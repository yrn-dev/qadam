@echo off
setlocal
set "PROJECT_DIR=%~dp0godot"
if defined GODOT_BIN goto found
where godot.exe >nul 2>nul
if not errorlevel 1 (set "GODOT_BIN=godot.exe" & goto found)
where godot4.exe >nul 2>nul
if not errorlevel 1 (set "GODOT_BIN=godot4.exe" & goto found)
echo Install Godot 4.4.1+ and add it to PATH, or set GODOT_BIN.
echo You can also import godot\project.godot in the Godot editor and press F5.
exit /b 1
:found
if exist "%PROJECT_DIR%\.godot\imported" goto launch
"%GODOT_BIN%" --headless --editor --path "%PROJECT_DIR%" --import
if errorlevel 1 exit /b 1
:launch
"%GODOT_BIN%" --path "%PROJECT_DIR%" %*
