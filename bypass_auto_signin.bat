@echo off
setlocal EnableDelayedExpansion

set "ADB_CMD="
where adb >nul 2>nul
if %errorlevel% equ 0 (
    set "ADB_CMD=adb"
) else if exist "%LOCALAPPDATA%\Microsoft\WinGet\Links\adb.exe" (
    set "ADB_CMD=%LOCALAPPDATA%\Microsoft\WinGet\Links\adb.exe"
) else if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" (
    set "ADB_CMD=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
)

if "%ADB_CMD%"=="" (
    echo Error: adb is not installed or not in your PATH.
    echo To install it on Windows, open Command Prompt or PowerShell and run:
    echo   winget install Google.PlatformTools
    echo Then close and reopen your window.
    pause
    exit /b 1
)

set "TARGET=%~1"
if "%TARGET%"=="" (
    set /p "TARGET=Enter Gemini Air IP address: "
)

set "TARGET=%TARGET: =%"
if "%TARGET%"=="" (
    echo Usage: %~nx0 ^<device-ip[:port]^>
    pause
    exit /b 1
)

set "HOST_IP=%TARGET%"
set "PORT=5555"
for /f "tokens=1,2 delims=:" %%a in ("%TARGET%") do (
    set "HOST_IP=%%a"
    if not "%%b"=="" set "PORT=%%b"
)
set "DEVICE=%HOST_IP%:%PORT%"

echo Connecting to %DEVICE%...
call :try_connect "%DEVICE%"
if !errorlevel! neq 0 (
    if not "%PORT%"=="5555" (
        echo Port %PORT% refused connection ^(Wireless Debugging shows a pairing port, while standard ADB uses 5555^).
        set "DEVICE=%HOST_IP%:5555"
        echo Retrying on !DEVICE!...
        call :try_connect "!DEVICE!"
        if !errorlevel! neq 0 (
            echo Error: Could not connect to !DEVICE!. Check the IP address and make sure USB debugging and Wireless debugging are enabled.
            pause
            exit /b 1
        )
    ) else (
        echo Error: Could not connect to %DEVICE%. Check the IP address and make sure USB debugging and Wireless debugging are enabled.
        pause
        exit /b 1
    )
)

echo Checking ADB authorization ^(check the TV screen and select Allow if prompted^)...
set "AUTHORIZED=0"
for /L %%i in (1,1,60) do (
    for /f "delims=" %%s in ('"%ADB_CMD%" -s "%DEVICE%" get-state 2^>nul') do (
        if "%%s"=="device" (
            set "AUTHORIZED=1"
            goto :auth_ok
        )
    )
    set /a "MOD=%%i %% 3"
    if !MOD! equ 0 (
        "%ADB_CMD%" connect "%DEVICE%" >nul 2>nul
    )
    timeout /t 1 /nobreak >nul
)

:auth_ok
if "%AUTHORIZED%" neq "1" (
    echo Error: Timed out waiting for ADB authorization on %DEVICE%.
    echo Select Allow on the TV prompt and run this script again.
    pause
    exit /b 1
)

powershell -NoProfile -Command "$c = Get-Content -Raw -LiteralPath '%~f0'; $s = ($c -split '# --- BEGIN_DEVICE_SCRIPT ---\r?\n', 2)[1] -replace \"`r\", ''; $s | & '%ADB_CMD%' -s '%DEVICE%' shell 'cat > /data/local/tmp/asi_bypass.sh && chmod 700 /data/local/tmp/asi_bypass.sh'"
if %errorlevel% neq 0 (
    echo Error: Failed to upload helper script to device.
    pause
    exit /b 1
)

"%ADB_CMD%" -s "%DEVICE%" shell "/system/bin/sh /data/local/tmp/asi_bypass.sh; rm -f /data/local/tmp/asi_bypass.sh"

echo Done. The TV should now be on the email login screen.
pause
exit /b 0

:try_connect
set "CONN_TMP=%TEMP%\asi_adb_%RANDOM%.txt"
"%ADB_CMD%" connect "%~1" > "%CONN_TMP%" 2>&1
type "%CONN_TMP%"
findstr /i /c:"connected to" /c:"already connected" /c:"failed to authenticate" "%CONN_TMP%" >nul 2>nul
set "CONN_RC=%errorlevel%"
del /q "%CONN_TMP%" >nul 2>nul
exit /b %CONN_RC%

# --- BEGIN_DEVICE_SCRIPT ---
#!/system/bin/sh

WATCHDOG_PID=""

cleanup_all() {
  rm -f /data/local/tmp/asi_bypass_active /data/local/tmp/asi_ui.xml
  settings put global http_proxy :0 >/dev/null 2>&1 || true
  settings delete global http_proxy >/dev/null 2>&1 || true
  settings delete global global_http_proxy_host >/dev/null 2>&1 || true
  settings delete global global_http_proxy_port >/dev/null 2>&1 || true
  if [ -n "$WATCHDOG_PID" ]; then
    kill "$WATCHDOG_PID" >/dev/null 2>&1 || true
  fi
}

dump_ui() {
  rm -f /data/local/tmp/asi_ui.xml
  uiautomator dump /data/local/tmp/asi_ui.xml >/dev/null 2>&1 || true
  if [ -f /data/local/tmp/asi_ui.xml ]; then
    cat /data/local/tmp/asi_ui.xml
  fi
}

input keyevent 224 >/dev/null 2>&1 || true
if dumpsys activity activities 2>/dev/null | grep -E "topResumedActivity|ResumedActivity" | grep -qiE "backdrop|dream"; then
  input keyevent 4 >/dev/null 2>&1 || true
  sleep 1
fi

touch /data/local/tmp/asi_bypass_active
nohup sh -c '
  i=0
  while [ "$i" -lt 35 ] && [ -f /data/local/tmp/asi_bypass_active ]; do
    sleep 1
    i=$((i + 1))
  done
  settings put global http_proxy :0 >/dev/null 2>&1
  settings delete global http_proxy >/dev/null 2>&1
  settings delete global global_http_proxy_host >/dev/null 2>&1
  settings delete global global_http_proxy_port >/dev/null 2>&1
  rm -f /data/local/tmp/asi_bypass_active /data/local/tmp/asi_ui.xml /data/local/tmp/asi_bypass.sh
' </dev/null >/dev/null 2>&1 &
WATCHDOG_PID=$!

trap cleanup_all EXIT INT TERM

if dumpsys account 2>/dev/null | grep -q "type=att.account.open-video}"; then
  echo "Blocking Auto Sign-In check via temporary local proxy..."
  settings put global http_proxy 127.0.0.1:1
  am force-stop com.att.ngc.core

  echo "Opening DirecTV Sign Out menu..."
  am start -a com.att.ngcsettings.dfw.ACCOUNT_SIGN_OUT -n com.att.tv.openvideo/com.att.ngcsettings.dfw.MainSettingsActivity >/dev/null 2>&1

  CLICKED_SIGNOUT=0
  i=0
  while [ "$i" -lt 12 ]; do
    UI=$(dump_ui)
    if printf '%s\n' "$UI" | grep -q 'resource-id="com.att.tv.openvideo:id/yes_button"'; then
      CLICKED_SIGNOUT=1
      break
    fi
    if printf '%s\n' "$UI" | grep -q 'text="Sign Out"'; then
      input keyevent 23
      CLICKED_SIGNOUT=1
      sleep 1
      break
    fi
    sleep 1
    i=$((i + 1))
  done

  if [ "$CLICKED_SIGNOUT" -eq 0 ]; then
    input keyevent 23
    sleep 2
  fi

  echo "Confirming Sign Out..."
  CONFIRMED_OK=0
  i=0
  while [ "$i" -lt 10 ]; do
    if ! dumpsys account 2>/dev/null | grep -q "type=att.account.open-video}"; then
      CONFIRMED_OK=1
      break
    fi
    UI=$(dump_ui)
    if printf '%s\n' "$UI" | grep -q 'resource-id="com.att.tv.openvideo:id/yes_button"'; then
      if printf '%s\n' "$UI" | tr '<' '\n' | grep 'com.att.tv.openvideo:id/yes_button' | grep -q 'focused="true"'; then
        input keyevent 23
      else
        input keyevent 22
        sleep 1
        input keyevent 23
      fi
      CONFIRMED_OK=1
      break
    fi
    sleep 1
    i=$((i + 1))
  done

  if [ "$CONFIRMED_OK" -eq 0 ]; then
    input keyevent 22
    sleep 1
    input keyevent 23
  fi
else
  echo "No active DirecTV profile signed in."
  if ! dumpsys activity activities 2>/dev/null | grep -E "topResumedActivity|ResumedActivity" | grep -q "CIAMUserLoginMainActivity"; then
    echo "Blocking Auto Sign-In check and launching login screen..."
    settings put global http_proxy 127.0.0.1:1
    am force-stop com.att.ngc.core
    am force-stop com.att.tv.openvideo
    am start -n com.att.tv.openvideo/com.att.ngctv.dfw.navigation.MainNavigationActivity >/dev/null 2>&1
  fi
fi

echo "Waiting for manual login screen..."
i=0
while [ "$i" -lt 20 ]; do
  RESUMED=$(dumpsys activity activities 2>/dev/null | grep -E "topResumedActivity|ResumedActivity" || true)
  if printf '%s\n' "$RESUMED" | grep -q "CIAMUserLoginMainActivity"; then
    UI=$(dump_ui)
    if printf '%s\n' "$UI" | grep -qE "ciam_login_email|Network issue encountered|Got it|Sign in"; then
      break
    fi
  fi
  sleep 1
  i=$((i + 1))
done

echo "Restoring internet connection..."
cleanup_all
WATCHDOG_PID=""

i=0
while [ "$i" -lt 5 ]; do
  UI=$(dump_ui)
  if printf '%s\n' "$UI" | grep -qE 'Network issue encountered|text="Got it"'; then
    echo "Dismissing network notice..."
    input keyevent 23
    sleep 1
  elif printf '%s\n' "$UI" | grep -q "ciam_login_email_input_container" && ! printf '%s\n' "$UI" | grep -q "ciam_login_loading_indicator"; then
    if [ "$i" -ge 1 ]; then
      break
    fi
  fi
  sleep 1
  i=$((i + 1))
done

rm -f /data/local/tmp/asi_ui.xml
