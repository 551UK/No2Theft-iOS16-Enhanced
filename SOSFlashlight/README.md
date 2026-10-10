# No2Theft Enhanced SOS flashlight
Optional iOS 16 Dopamine/rootless SOS rear torch (··· ——— ···) for No2Theft Enhanced 1.3.1.

When enabled in No2Theft Settings (`sosFlashlight` in `com.elias.no2theft3`), detects No2Theft's own alarm player, repeats SOS indefinitely with no time limit while the alarm is active, and turns the rear torch off on alarm stop/pause or when disarmed. No GPS request, daemon, or idle flashing. Original photo/email/GPS binaries are unchanged.

This folder builds only the new injected helper. Merge its compiled dylib and filter into the **existing** v1.3.1 DEB along with the new Settings switch to make a single No2Theft Enhanced package. Keep v1.3.1 as a rollback.

Test on-device, especially alarm disarm by PIN and Face ID; this code has not yet been verified on-device.
