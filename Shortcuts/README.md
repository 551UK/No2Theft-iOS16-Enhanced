# No2Theft Gmail Email Fix + one-shot Shortcuts location test

This source is an **experimental** integration. It must be tested on XS Max iOS 16.3.1 (Dopamine rootless). The user's confirmed working base package is No2Theft Email Fix Test 4 v1.1+smtp-test4, whose No2Theft.dylib must be copied unchanged into the combined package.

On an alarm email whose message has an old IP-derived Google Maps URL, N2TShortcutGPS temporarily intercepts SKPSMTPMessage send. It spawns **N2TShortcutLocation only on demand** (via posix_spawn), runs a two-action Shortcuts workflow: `is.workflow.actions.getcurrentlocation` then `is.workflow.actions.getmapslink`, extracts the map link, replaces the old London link, then sends the original SMTP message with its photo unchanged. On failure or timeout (maximum about 25 seconds), email is still sent, with `GPS location unavailable (Shortcuts: <status>)` rather than false IP-based coordinates.

This uses the *same API design* as the owner's working Watusi Scheduled Message Fix, but Watusi source, binary, entitlements, package and files are **not modified**. All executable names, filter plist, result locations and package identities are different. The helper exits as soon as it has a result; there is no resident daemon, persistent background process, continuous location tracking or background polling. A brief 0.25 s result-file check runs only while an alarm email is waiting.

**Unverified assumption:** Get Current Location declares Background as an unsupported Shortcuts environment. The OS may reject the workflow while locked, or require permission; this is precisely what Test 1 measures. An on-device test is needed; building is not proof the action runs under lock.

Last diagnostic status (no coordinates): `/var/mobile/Library/Preferences/uk.551.no2theft.shortcutloc.last.plist`. The helper's temporary result (may contain a map URL) is deleted immediately after reading.

Build: use the `Shortcuts/` Theos project (rootless, arm64+arm64e) to obtain a companion addon, then merge its dylib, plist and /var/jb/usr/bin/N2TShortcutLocation executable into the user's known-good base DEB with the same rootless path. Never add a second copy of Watusi or install any of its helper files. Installed package should replace earlier No2Theft Email Fix as version `1.1+smtp-test4+shortcuts1`.

**Testing safety:** The helper is experimental, so test with a recovery plan; it hooks SpringBoard's email sending. Do not uninstall or modify the user's Watusi Scheduled Message Fix. Old v0.5 diagnostic bridge should be removed so only this code affects No2Theft.
