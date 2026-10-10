# No2Theft one-shot authorized location — Test 4

The working Gmail SMTP/photo Email Fix Test 4 base package is preserved **byte-for-byte for all 34 original payload files**. This branch builds an experimental one-shot CoreLocation provider and a late-loading SMTP URL replacement hook.

## Why this test differs

On iPhone XS Max iOS 16.3.1:
- Native GPS Check GUI returned real GPS with iOS When In Use permission.
- The same GUI received 44 callbacks while location tracking was started before the phone was locked.
- SpringBoard direct CoreLocation returned `kCLErrorDenied` with authorization 0.
- Waking a suspended GPS app using Darwin notification failed: only delivered after unlock.
- Watusi-inspired Shortcuts execution returned `workflow_timeout` and `workflow_timeout_no_start`. Apple's Shortcuts action `is.workflow.actions.getcurrentlocation` declares Background an unsupported environment.

This experimental Test 4 uses **the same executable** for the permission GUI and the alarm-time headless GPS request. Launching the app executable as a subprocess might preserve its bundle identity for location permission, but this has **not yet been proven**. No background daemon, continuous GPS, periodic timer or permanent helper is installed. On an email alert, the separate process runs up to 18 seconds then exits. The email hook imposes a 20-second deadline; even on failure, the original Gmail/photo email is sent without a false London map pin.

## Test procedure

1. Remove any earlier GPS Check/diagnostic bridge packages, but keep Watusi installed. They are independent.
2. Install the combined DEB produced by merging the two rootless packages built in this branch into the original Email Fix Test 4 DEB; version `1.2+onceloc1`, package ID `xyz.cypwn.no2theft16`.
3. Respring; launch **No2Theft Location** from the Home Screen.
4. Tap **Allow Location** and allow While Using, then **Request Always Permission**. iOS may defer the Always upgrade, and must be allowed to ask. **Permission 4 means Always; 3 means While Using.** Nothing is tracked continuously even if Always is granted.
5. Tap **Check GPS Now** to verify foreground location works, then close the app.
6. Trigger a safe No2Theft test email *while the phone is locked*, then wait up to around 25 seconds.
7. Email will either have a real map URL or `GPS location unavailable (On-demand: <status>)`. Last status only (no coordinates) is in `/var/mobile/Library/Preferences/uk.551.no2theft.onceloc.last.plist`.

If the app's headless process is not attributed the same bundle location permission, expect `permission_not_determined` or `permission_denied`. If launching in the background cannot obtain GPS even with Always, expect `clerror_1` or `location_timeout`. Do not keep GPS running continuously to mask this issue.

Built from:
- `OneShot/LocationApp/main.m` (GUI + `--once <UUID>` headless mode)
- `OneShot/EmailHook.m` (SpringBoard `SKPSMTPMessage send` interception)
- `OneShot/Makefile` and `OneShot/LocationApp/Makefile`

The app's run mode is only activated when the email hook spawns it. Temporary coordinate files are permissions 0600 and deleted after the hook reads them. Only the last status is kept, for debugging. No Watusi files, binaries, prefs or hooks are part of this build. All other email and photo code is preserved.

**Known limitation:** the old Country/City/Region fields remain IP-derived, so `City = London` may still appear even when the Google Maps link has been replaced. Their clean-up can follow after GPS itself succeeds.

## Caution

The provider and integration are experimental and not yet verified on an XS Max while locked. An iOS app's `requestAlwaysAuthorization` normally requires an in-app permission UI, and a CLI process might not receive the same authorized identity. Maintain access to the original working Email Fix package if a regression occurs.
