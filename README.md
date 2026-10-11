# No2Theft Enhanced iOS16

**By 551UK & Elias Sfeir** — iOS 16, Dopamine rootless.

Enhanced theft protection for jailbroken iPhones, retaining the original No2Theft alarm and PIN controls.

## Enhancements in v4.2

- **SMS alerts restored:** Choose up to two recipient numbers. Send SMS alerts when the alarm triggers, or when a configured remote SMS command is received.
- **Real GPS location:** Uses the iPhone's location services rather than IP-based location, correcting Google Maps coordinates in SMS and email alerts.
- **SOS flashlight:** Repeating SOS light pattern helps locate a missing iPhone when the alarm activates.
- **Remote commands:** Your configured remote phrases can activate the alarm and its enabled SMS, email, photo and SOS features.
- **Photo Crash Guard:** Helps prevent iOS 16's legacy photo-capture exception from crashing SpringBoard.
- **Single Settings page:** SMS, remote commands, PIN, email and other settings are together.

**Important:** Open the **No2Theft Location** app on your Home Screen and allow Location Access with **Precise Location** enabled for accurate GPS in email and SMS alerts.

## Quick Gmail SMTP setup

1. In your Google Account, turn on **2-Step Verification**, then open [Google App Passwords](https://myaccount.google.com/apppasswords). Generate an app password for No2Theft. App passwords may be unavailable on some accounts.
2. On iPhone, open **Settings → No2Theft Enhanced iOS16** and enable **Send Email** in Email settings.
3. Enter the address that should **receive** alerts in **Receiver email address**.
4. Under **GMAIL SMTP**, enable **Use Custom SMTP**. Enter your Gmail address under **Sender Gmail** and the **16-character app password** under **Gmail App Password** (not your usual Gmail password).
5. Tap **Apply Changes**, respring if prompted, then test an alert. For remote-command email alerts, enable the relevant **Send Email** option under Remote Commands as well.

**Privacy note:** No2Theft stores its Gmail app password without encryption. Use a dedicated app password and revoke it from your Google Account if the phone is lost or the tweak is removed.

## Download

[Latest v4.2 release](https://github.com/551UK/No2Theft-iOS16-Enhanced/releases/tag/v4.2)

The [earlier stable v1.3.5](https://github.com/551UK/No2Theft-iOS16-Enhanced/releases/tag/v1.3.5) is retained as a rollback option.

Package ID: `xyz.cypwn.no2theft16`.
