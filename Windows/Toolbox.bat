@echo off
:: ============================================================
::  System Toolbox - avvio con interfaccia grafica
::
::  Questo file esiste solo per permettere il doppio clic.
::  Tutta la logica sta in Toolbox.ps1, che si occupa anche
::  dell'elevazione dei privilegi e, se WPF non fosse
::  disponibile, ricade da solo sul menu testuale.
::
::  -STA e' richiesto da WPF.
::
::  Parametri accettati (inoltrati allo script PowerShell):
::    -Console   forza il menu testuale
::    -Auto      manutenzione consigliata senza domande
::    -DryRun    simulazione, non modifica nulla
:: ============================================================

title System Toolbox

if not exist "%~dp0Toolbox.ps1" (
    echo.
    echo  [ERRORE] Toolbox.ps1 non trovato accanto a questo file.
    echo.
    pause
    exit /b 1
)

powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Toolbox.ps1" %*
set "RC=%errorlevel%"

if not "%RC%"=="0" (
    echo.
    echo  Lo script e' terminato con codice %RC%.
    pause
)

exit /b %RC%
