#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if ! command -v adb >/dev/null 2>&1; then
  echo "Error: adb is not installed. On macOS, run: brew install android-platform-tools"
  exit 1
fi

TARGET="${1:-}"
if [[ -z "${TARGET}" ]]; then
  read -r -p "Enter Gemini Air IP address: " TARGET
fi

if [[ -z "${TARGET}" ]]; then
  echo "Usage: $0 <device-ip[:port]>"
  exit 1
fi

# Default to port 5555 if no port was specified
if [[ "${TARGET}" != *:* ]]; then
  DEVICE="${TARGET}:5555"
else
  DEVICE="${TARGET}"
fi

echo "Connecting to ${DEVICE}..."
adb connect "${DEVICE}"

echo "Waiting for ADB authorization (check the TV screen and click Allow if prompted)..."
adb -s "${DEVICE}" wait-for-device

cleanup_proxy() {
  adb -s "${DEVICE}" shell '
    settings put global http_proxy :0 >/dev/null 2>&1 || true
    settings delete global http_proxy >/dev/null 2>&1 || true
    settings delete global global_http_proxy_host >/dev/null 2>&1 || true
    settings delete global global_http_proxy_port >/dev/null 2>&1 || true
  ' >/dev/null 2>&1 || true
}
trap cleanup_proxy EXIT

echo "Blocking Auto Sign-In check via temporary local proxy..."
adb -s "${DEVICE}" shell '
  settings put global http_proxy 127.0.0.1:1
  am force-stop com.att.ngc.core
'

echo "Signing out of current DirecTV profile..."
adb -s "${DEVICE}" shell '
  am start -a com.att.ngcsettings.dfw.ACCOUNT_SIGN_OUT -n com.att.tv.openvideo/com.att.ngcsettings.dfw.MainSettingsActivity >/dev/null
  sleep 4
  input keyevent 23
  sleep 2
  input keyevent 22
  sleep 1
  input keyevent 23
'

echo "Waiting for manual login screen..."
for _ in {1..15}; do
  RESUMED=$(adb -s "${DEVICE}" shell 'dumpsys activity activities | grep -E "topResumedActivity|ResumedActivity"' || true)
  if echo "${RESUMED}" | grep -q "CIAMUserLoginMainActivity"; then
    break
  fi
  sleep 1
done

sleep 2

echo "Restoring internet connection..."
cleanup_proxy

# Dismiss the "Network issue encountered" ("Got it") prompt if it popped up
UI_XML=$(adb -s "${DEVICE}" shell 'uiautomator dump /data/local/tmp/ui.xml >/dev/null 2>&1 && cat /data/local/tmp/ui.xml && rm -f /data/local/tmp/ui.xml' || true)
if echo "${UI_XML}" | grep -q "Network issue encountered\|Got it"; then
  adb -s "${DEVICE}" shell 'input keyevent 23'
  sleep 1
fi

echo "Done. The TV should now be on the email login screen."
