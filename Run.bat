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
echo           '--....--'         Powered by @mrstalex (IG)
echo   ---------------------------------------------------------------
echo.
echo   1. Simulate (measure only, change nothing)  / Simular
echo   2. Apply (max 100 ms, 4 servers)            / Aplicar
echo   3. Apply with custom settings               / Aplicar personalizado
echo   4. Status                                   / Estado
echo   5. Remove all rules                         / Quitar todo
echo   6. Exit                                     / Salir
echo.
choice /c 123456 /n /m "  Choose / Elige [1-6]: "
if errorlevel 6 goto :eof
if errorlevel 5 goto remove
if errorlevel 4 goto status
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
set "MAXPING=100"
set "MAXSRV=4"
set /p "MAXPING=  Max ping in ms / Ping maximo en ms [100]: "
set /p "MAXSRV=  Max servers, 0 = no limit / Maximo de servidores, 0 = sin limite [4]: "
%PS% -Mode Apply -MaxPing %MAXPING% -MaxServers %MAXSRV%
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
