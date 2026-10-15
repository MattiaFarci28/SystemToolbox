@echo off
:: ============================================================
::  System Toolbox - avvio con il menu testuale
::
::  Stesse identiche funzioni della versione grafica: cambia
::  solo l'interfaccia. Utile per uso da terminale, sessioni
::  remote o quando si preferisce la tastiera.
:: ============================================================

title System Toolbox - console

if not exist "%~dp0Toolbox.ps1" (
    echo.
    echo  [ERRORE] Toolbox.ps1 non trovato accanto a questo file.
    echo.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Toolbox.ps1" -Console %*
set "RC=%errorlevel%"

if not "%RC%"=="0" (
    echo.
    echo  Lo script e' terminato con codice %RC%.
    pause
)

exit /b %RC%
