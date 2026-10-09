# No2Theft iOS 16 GPS location add-on — experimental

**Source-only at present; it has not been compiled or tested on an iPhone.**

The companion tweak intercepts No2Theft's `ipinfo.io` lookup in the AFNetworking email path and substitutes a GPS-only result from the `INTULocationManager` class already bundled with No2Theft.

- It accepts a GPS fix only if its coordinates are valid, its reported horizontal accuracy is **30 m or better**, and its timestamp is **no more than 20 seconds old**.
- It waits up to **12 seconds** for a location.
- It **does not fall back to IP geolocation** once interception is active.
- With no qualifying GPS fix, the email's coordinate field reads `GPS unavailable`, rather than presenting a misleading IP position.
- The original Email Fix, Gmail settings, recipient, photograph and email wording are untouched. Install as a *separate* package.

## Build and test

Use the manual GitHub Actions workflow on the default branch to build the `gps-test` branch, then download its artifact and install the generated rootless DEB **alongside** No2Theft iOS 16 (Email Fix). Alternatively, use a configured macOS Theos rootless toolchain and run `make clean package FINALPACKAGE=1`.

**Important limitations:** This add-on has no on-device validation yet. Hooks may not attach if AFNetworking or INTULocationManager have not loaded before its constructor runs, in which case the original IP email path may remain active. No2Theft might have other email paths not intercepted here. Verify the source of every location alert before relying on this tweak, and keep an uninstall/recovery plan given prior Safe Mode and passcode lockout reports. Do not deliberately enter incorrect passcodes to test.

**Privacy:** This repository must not contain the original No2Theft binary, the SMTP password, account details or personal location logs.
