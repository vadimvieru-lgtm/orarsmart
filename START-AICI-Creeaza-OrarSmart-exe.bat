@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
title Creez OrarSmart.exe
echo ==================================================
echo   Creez programul OrarSmart.exe
echo   Prima data dureaza 3-6 minute. Trebuie internet.
echo   Nu inchide aceasta fereastra.
echo ==================================================
echo.
set "NODEVER=22.11.0"
set "TOOLS=%~dp0.tools"
if exist "%TOOLS%\node\node.exe" goto havenode
echo [1/3] Descarc Node.js portabil (nu se instaleaza nimic in Windows)...
mkdir "%TOOLS%" 2>nul
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest 'https://nodejs.org/dist/v%NODEVER%/node-v%NODEVER%-win-x64.zip' -OutFile '%TOOLS%\node.zip'; Expand-Archive '%TOOLS%\node.zip' '%TOOLS%' -Force; Rename-Item '%TOOLS%\node-v%NODEVER%-win-x64' 'node'; Remove-Item '%TOOLS%\node.zip'"
if not exist "%TOOLS%\node\node.exe" goto fail
:havenode
set "PATH=%TOOLS%\node;%PATH%"
echo [2/3] Descarc componentele programului...
call npm install --no-audit --no-fund
if errorlevel 1 goto fail
echo [3/3] Construiesc OrarSmart.exe...
call npm run pack
if errorlevel 1 goto fail
set "OUT=%~dp0dist\OrarSmart-win32-x64"
if not exist "%OUT%\OrarSmart.exe" goto fail
powershell -NoProfile -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut([Environment]::GetFolderPath('Desktop')+'\OrarSmart.lnk');$s.TargetPath='%OUT%\OrarSmart.exe';$s.WorkingDirectory='%OUT%';$s.Save()"
echo.
echo ==================================================
echo   GATA! Programul este in:
echo   %OUT%\OrarSmart.exe
echo   Am pus si o scurtatura "OrarSmart" pe Desktop.
echo ==================================================
start "" "%OUT%\OrarSmart.exe"
start "" "%OUT%"
pause
exit /b 0
:fail
echo.
echo EROARE: ceva nu a mers. Verifica conexiunea la internet si ruleaza din nou.
echo Daca persista, fa o poza ferestrei si trimite-mi-o.
pause
exit /b 1
