@echo off
setlocal EnableDelayedExpansion

where adb >nul 2>nul
if %errorlevel% neq 0 (
    echo Error: adb is not installed or not in your PATH.
    echo To install it on Windows, open Command Prompt or PowerShell and run:
    echo   winget install Google.PlatformTools
    echo Then close and reopen your terminal window.
    pause
    exit /b 1
)

set "TARGET=%~1"
if "%TARGET%"=="" (
    set /p "TARGET=Enter Gemini Air IP address: "
)

if "%TARGET%"=="" (
    echo Usage: %~nx0 ^<device-ip[:port]^>
    pause
    exit /b 1
)

echo %TARGET% | find ":" >nul
if %errorlevel% equ 0 (
    set "DEVICE=%TARGET%"
) else (
    set "DEVICE=%TARGET%:5555"
)

echo Connecting to %DEVICE%...
adb connect %DEVICE%

echo Waiting for ADB authorization (check the TV screen and click Allow if prompted)...
adb -s %DEVICE% wait-for-device

echo Blocking Auto Sign-In check via temporary local proxy...
adb -s %DEVICE% shell "settings put global http_proxy 127.0.0.1:1 && am force-stop com.att.ngc.core"

echo Signing out of current DirecTV profile...
adb -s %DEVICE% shell "am start -a com.att.ngcsettings.dfw.ACCOUNT_SIGN_OUT -n com.att.tv.openvideo/com.att.ngcsettings.dfw.MainSettingsActivity >/dev/null && sleep 4 && input keyevent 23 && sleep 2 && input keyevent 22 && sleep 1 && input keyevent 23"

echo Waiting for manual login screen...
for /L %%i in (1,1,15) do (
    adb -s %DEVICE% shell "dumpsys activity activities | grep -q CIAMUserLoginMainActivity" >nul 2>nul
    if !errorlevel! equ 0 goto :found_login
    timeout /t 1 /nobreak >nul
)

:found_login
timeout /t 2 /nobreak >nul

echo Restoring internet connection...
adb -s %DEVICE% shell "settings put global http_proxy :0 >/dev/null 2>&1; settings delete global http_proxy >/dev/null 2>&1; settings delete global global_http_proxy_host >/dev/null 2>&1; settings delete global global_http_proxy_port >/dev/null 2>&1"

adb -s %DEVICE% shell "uiautomator dump /data/local/tmp/ui.xml >/dev/null 2>&1 && grep -q -E 'Network issue encountered|Got it' /data/local/tmp/ui.xml && input keyevent 23; rm -f /data/local/tmp/ui.xml" >nul 2>nul

echo Done. The TV should now be on the email login screen.
pause
