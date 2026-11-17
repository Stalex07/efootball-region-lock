@echo off
setlocal
title eFootball Region Lock
set "SELF=%~f0"

net session >nul 2>&1
if %errorlevel% equ 0 goto admin
echo Requesting administrator rights...
powershell -NoProfile -Command "Start-Process -FilePath $env:SELF -Verb RunAs"
exit /b

:admin
cd /d "%~dp0"
set "PS=powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0eFootball-RegionLock.ps1""

:menu
cls
echo.
echo          _...----..._
echo        .'  \  __  /  '.      )  )  )
echo       /  ---\/  \/---  \
echo      ^|      ^|    ^|      ^|    eFootball Region Lock
echo       \  ---/\__/\---  /     Play on servers close to you
echo        '._ /      \ _.'
echo           '--....--'         Powered by @mrstalex
echo   ---------------------------------------------------------------
echo.
echo   SERVERS / SERVIDORES
echo   1. Simulate (measure only, change nothing)  / Simular
echo   2. Apply (max 100 ms, 4 servers)            / Aplicar
echo   3. Apply with custom settings               / Aplicar personalizado
echo   4. Choose regions by hand                   / Elegir regiones a mano
echo.
echo   DURING A MATCH / DURANTE UN PARTIDO
echo   5. Check current match server               / Revisar partido actual
echo   6. Live monitor (ping, jitter, loss)        / Monitor en vivo
echo.
echo   OTHER / OTROS
echo   7. Match history                            / Historial de partidos
echo   8. Status                                   / Estado
echo   9. Remove all rules                         / Quitar todo
echo   0. Exit                                     / Salir
echo.
choice /c 1234567890 /n /m "  Choose / Elige [0-9]: "
if errorlevel 10 goto :eof
if errorlevel 9 goto remove
if errorlevel 8 goto status
if errorlevel 7 goto history
if errorlevel 6 goto monitor
if errorlevel 5 goto match
if errorlevel 4 goto pick
if errorlevel 3 goto custom
if errorlevel 2 goto apply
if errorlevel 1 goto dryrun

:dryrun
%PS% -Mode DryRun
pause
goto menu

:apply
%PS% -Mode Apply
pause
goto menu

:custom
rem The values are asked and validated inside PowerShell, never passed through CMD.
%PS% -Mode Apply -AskSettings
pause
goto menu

:pick
%PS% -Mode Pick
pause
goto menu

:match
%PS% -Mode Match
pause
goto menu

:monitor
%PS% -Mode Monitor
pause
goto menu

:history
%PS% -Mode History
pause
goto menu

:status
%PS% -Mode Status
pause
goto menu

:remove
%PS% -Mode Remove
pause
goto menu
