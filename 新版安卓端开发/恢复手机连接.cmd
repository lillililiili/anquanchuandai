@echo off
setlocal
set "PHONE_ADB=C:\leidian\LDPlayer14\adb.exe"
set "PHONE_SERIAL=6HUGIJZLDM8PRWG6"
if not exist "%PHONE_ADB%" goto missing_adb
"%PHONE_ADB%" -s "%PHONE_SERIAL%" get-state >nul 2>&1
if errorlevel 1 goto disconnected
"%PHONE_ADB%" -s "%PHONE_SERIAL%" shell toybox nc -z -w 5 10.137.74.38 18084
if errorlevel 1 goto failed
echo Direct TCP connection to the computer at 10.137.74.38:18084 is ready.
echo No adb port forwarding is created by this script.
echo This address currently uses USB networking. Keep that network connected.
echo The Docker backend must also be running on port 18084.
if not "%~1"=="--no-pause" pause
exit /b 0
:missing_adb
echo LDPlayer adb was not found at "%PHONE_ADB%".
goto failed
:disconnected
echo Connect and unlock the Redmi phone, then allow USB debugging.
:failed
echo Direct connection check FAILED. Check the network, IP and backend.
if not "%~1"=="--no-pause" pause
exit /b 1
