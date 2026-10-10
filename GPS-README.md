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

## Single Sileo package (Email + GPS Fix)

For personal testing, you can combine an **already working Email Fix DEB** and the generated **GPS add-on DEB** into one installable package using:

```bash
bash scripts/make-combined-deb.sh No2Theft-iOS16-Email-Fix-rootless.deb No2Theft-iOS16-GPS-Only-Experimental-rootless.deb
```

The result is titled `No2Theft iOS 16 (Email + GPS Fix)` in Sileo and retains the existing No2Theft package identifier and preferences. It declares a conflict/replacement with the separately installed GPS add-on so the older add-on must be removed during installation. Both compiled dylibs remain exactly unchanged; this is a **single package**, not a fully merged binary.

The repository does not distribute the underlying No2Theft binary, which must be supplied separately by its owner. The GPS add-on is experimental and has not yet been validated to produce a precise live GPS pin on a physical iOS 16 device. Avoid passcode-triggered tests given the prior lockout.

## GPS Link Fix Test 2 (2026-10-10)

The earlier GPS Test 1 intercepted AFNetworking's IPInfo request and fabricated a response, and was observed to enter Safe Mode on an iPhone XS Max. **Do not use Test 1.**

Test 2 changes the implementation to hook the existing SMTP message's `send` selector, request a fresh CoreLocation position, and replace only the Google Maps coordinate URL in the outgoing message body. The original Gmail SMTP and alarm binaries remain unchanged in the combined package.

A GPS position must be at most 20 seconds old and have horizontal accuracy of at most 30 m. If it is unavailable after approximately 13 seconds, the link becomes `GPS location unavailable`; Test 2 never inserts a guessed IP coordinate into that map URL when its hook runs.

**Not yet verified on a phone.** The original IP lookup and City/Region/Country fields remain unchanged in Test 2; only the map URL is targeted. Test using a safe alarm trigger, not failed passcodes. Review any crash logs before further changes.
