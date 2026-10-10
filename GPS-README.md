# No2Theft iOS 16 — GPS Link Fix (experimental)

This project produces a rootless Dopamine iOS 16 tweak that uses CoreLocation to replace the **Google Maps link** in No2Theft alarm emails. It keeps the known-good Test 4 Gmail sender, recipients, original email text, photos, and alarm code unchanged.

## Current test: GPS 4 (no accuracy or age filters)

The outgoing email intercept obtains a location through the INTULocationManager class already in No2Theft.

- It requests the highest GPS accuracy available.
- It accepts **any valid GPS coordinates iOS returns**, without filtering by reported metres of accuracy, GPS reading age, or location provider status.
- It waits up to approximately 24 seconds so an email won't hang indefinitely if location services cannot supply coordinates.
- It replaces only the existing Google Maps URL; if there are no coordinates at all, the email says GPS location unavailable (with a short diagnostic reason).
- It never substitutes IP-based coordinates in the map URL. However, the legacy City/Region/Country and public IP text fields remain IP-derived for now.
- The source lives on the `gps-test` branch. The CI build outputs a **GPS add-on**, which can be merged with an owned, working Email Fix DEB using `scripts/make-combined-deb.sh` to produce one Sileo package (version `1.1+smtp-test4+gps4`).

**Limitations:** Source compilation succeeded, but the new GPS location link has **not yet been confirmed on a physical device**. Since age and accuracy filters are disabled as requested, any location returned may be old or approximate; CoreLocation cannot guarantee a truly current or precise fix. The code also still relies on No2Theft's location authorization in SpringBoard, which can differ from Google Maps' authorization.

## Recovery

A prior GPS implementation that fabricated an AFNetworking reply triggered SpringBoard Safe Mode on an iPhone XS Max, and should not be reused. Keep a backup of the known-good Email Fix Test 4 and test only with a safe trigger; do not deliberately enter wrong lock-screen passcodes.

This GitHub repository hosts companion source only, never Gmail passwords, user preferences, private location logs, or No2Theft's original proprietary binary.
