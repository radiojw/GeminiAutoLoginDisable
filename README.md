# GeminiAutoLoginDisable

If you get a used DirecTV Gemini or Gemini Air, it often has Auto Sign-In enabled from whoever owned it before. When you sign out or factory reset the box, it reaches out to DirecTV's servers during setup and logs right back into the old account before you can enter your own credentials.

A common workaround is to block the device from the internet on your router right as it boots or signs out so the auto-login check fails and drops you at the regular login screen.

This script does the same thing over network ADB without needing router rules or a factory reset. It sets a temporary dead proxy (`127.0.0.1:1`) on the device, signs out of the current profile, waits for the auto-login check to fail and load the manual email/password screen, and then clears the proxy so you can sign in with your own DirecTV account.

## Step 1: Enable ADB on the Gemini Air

1. On the Gemini Air, open **Settings** -> **System** -> **About**.
2. Scroll down to **Android TV OS build** and press **OK** on the remote 7 times until it says Developer options are enabled.
3. Press Back to return to **System**, then open **Developer options**.
4. Turn on **USB debugging** and **Wireless debugging**.
5. Note the IP address shown under Wireless debugging (or check **Settings** -> **Network & Internet**). The device listens on standard ADB port `5555` once debugging is enabled.

## Step 2: Run the script

### Windows

1. Open Command Prompt or PowerShell and install `adb` using winget:

```powershell
winget install Google.PlatformTools
```

*(Close and reopen your Command Prompt / PowerShell window after installing so `adb` is in your PATH.)*

2. Download or clone this repository, then either double-click `bypass_auto_signin.bat` (it will ask for your Gemini Air IP address) or run it from Command Prompt / PowerShell:

```bat
bypass_auto_signin.bat 192.168.1.50
```

### macOS / Linux

1. Install `adb` if you don't already have it (on macOS with Homebrew):

```bash
brew install android-platform-tools
```

2. Run the script with your device's IP address:

```bash
chmod +x bypass_auto_signin.sh
./bypass_auto_signin.sh 192.168.1.50
```

---

When prompted on the TV screen, check **Always allow from this computer** and select **Allow**.

After about 10 seconds, the old account will be signed out and the TV will stay on the **"First, we need your email"** login screen with normal internet access restored.
