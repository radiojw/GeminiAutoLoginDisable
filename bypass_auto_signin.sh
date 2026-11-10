#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if ! command -v adb >/dev/null 2>&1; then
  echo "Error: adb is not installed."
  echo "  macOS:         brew install android-platform-tools"
  echo "  Ubuntu/Debian: sudo apt install adb"
  echo "  Fedora:        sudo dnf install android-tools"
  echo "  Arch Linux:    sudo pacman -S android-tools"
  exit 1
fi

TARGET="${1:-}"
if [[ -z "${TARGET}" ]]; then
  read -r -p "Enter Gemini Air IP address: " TARGET
fi

# Strip any accidental spaces
TARGET="${TARGET//[[:space:]]/}"

if [[ -z "${TARGET}" ]]; then
  echo "Usage: $0 <device-ip[:port]>"
  exit 1
fi

if [[ "${TARGET}" == *:* ]]; then
  HOST_IP="${TARGET%%:*}"
  PORT="${TARGET##*:}"
else
  HOST_IP="${TARGET}"
  PORT="5555"
fi
DEVICE="${HOST_IP}:${PORT}"

try_connect() {
  local dev="$1"
  local out
  out=$(adb connect "${dev}" 2>&1 || true)
  echo "${out}"
  if echo "${out}" | grep -qiE "connected to|already connected|failed to authenticate"; then
    return 0
  fi
  return 1
}

echo "Connecting to ${DEVICE}..."
if ! try_connect "${DEVICE}"; then
  if [[ "${PORT}" != "5555" ]]; then
    echo "Port ${PORT} refused connection (Wireless Debugging shows a pairing port, while standard ADB uses 5555)."
    DEVICE="${HOST_IP}:5555"
    echo "Retrying on ${DEVICE}..."
    if ! try_connect "${DEVICE}"; then
      echo "Error: Could not connect to ${DEVICE}. Check the IP address and make sure USB debugging and Wireless debugging are enabled."
      exit 1
    fi
  else
    echo "Error: Could not connect to ${DEVICE}. Check the IP address and make sure USB debugging and Wireless debugging are enabled."
    exit 1
  fi
fi

echo "Checking ADB authorization (check the TV screen and select 'Allow' if prompted)..."
AUTHORIZED=0
for i in {1..60}; do
  STATE=$(adb -s "${DEVICE}" get-state 2>&1 || true)
  if [[ "${STATE}" == "device" ]]; then
    AUTHORIZED=1
    break
  fi
  if (( i % 3 == 0 )); then
    adb connect "${DEVICE}" >/dev/null 2>&1 || true
  fi
  sleep 1
done

if [[ "${AUTHORIZED}" -ne 1 ]]; then
  echo "Error: Timed out waiting for ADB authorization on ${DEVICE}."
  echo "Select 'Allow' on the TV prompt and run this script again."
  exit 1
fi

cleanup_host() {
  adb -s "${DEVICE}" shell '
    rm -f /data/local/tmp/asi_bypass_active /data/local/tmp/asi_ui.xml /data/local/tmp/asi_bypass.sh
    settings put global http_proxy :0 >/dev/null 2>&1 || true
    settings delete global http_proxy >/dev/null 2>&1 || true
    settings delete global global_http_proxy_host >/dev/null 2>&1 || true
    settings delete global global_http_proxy_port >/dev/null 2>&1 || true
  ' >/dev/null 2>&1 || true
}
trap cleanup_host EXIT INT TERM

# Upload and run the on-device script (with its own failsafe timer in case Wi-Fi or terminal drops)
cat <<'DEVICE_EOF' | adb -s "${DEVICE}" shell 'cat > /data/local/tmp/asi_bypass.sh && chmod 700 /data/local/tmp/asi_bypass.sh'
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

# Wake display and exit screensaver if active
input keyevent 224 >/dev/null 2>&1 || true
if dumpsys activity activities 2>/dev/null | grep -E "topResumedActivity|ResumedActivity" | grep -qiE "backdrop|dream"; then
  input keyevent 4 >/dev/null 2>&1 || true
  sleep 1
fi

# Start a 35-second on-device failsafe timer so the box never stays stuck offline if disconnected
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

  # Wait until "Sign Out" appears on screen before clicking it
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

# Dismiss "Network issue encountered" ("Got it") if shown, without clicking Next on the email screen
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
DEVICE_EOF

adb -s "${DEVICE}" shell '/system/bin/sh /data/local/tmp/asi_bypass.sh; rm -f /data/local/tmp/asi_bypass.sh'

echo "Done. The TV should now be on the email login screen."
