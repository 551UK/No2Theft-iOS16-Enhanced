#!/usr/bin/env bash
# Merge a locally obtained, working Email Fix DEB with the GPS add-on DEB.
# Does not upload original No2Theft binaries or any email credentials to GitHub.
set -euo pipefail
if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 EMAIL_FIX.deb GPS_ADDON.deb [COMBINED.deb]" >&2
  exit 2
fi
EMAIL_DEB=$(realpath "$1")
GPS_DEB=$(realpath "$2")
OUTPUT=$(realpath -m "${3:-No2Theft-iOS16-Email-GPS-Fix-rootless.deb}")
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
dpkg-deb -R "$EMAIL_DEB" "$WORK/email"
dpkg-deb -R "$GPS_DEB" "$WORK/gps"
EMAIL_ID=$(dpkg-deb -f "$EMAIL_DEB" Package)
GPS_ID=$(dpkg-deb -f "$GPS_DEB" Package)
if [[ "$EMAIL_ID" != "xyz.cypwn.no2theft16" || "$GPS_ID" != "uk.551.no2theft.gps" ]]; then
  echo "Unexpected package identifier(s); refusing to build." >&2
  exit 1
fi
cp -a "$WORK/email" "$WORK/combined"
LIB=var/jb/Library/MobileSubstrate/DynamicLibraries
for f in ZZNo2TheftGPS.dylib ZZNo2TheftGPS.plist; do
  test -f "$WORK/gps/$LIB/$f"
  cp -p "$WORK/gps/$LIB/$f" "$WORK/combined/$LIB/$f"
done
cat > "$WORK/combined/DEBIAN/control" <<'EOF'
Package: xyz.cypwn.no2theft16
Name: No2Theft iOS 16 (Email + GPS Fix)
Version: 1.1+smtp-test4+gps4
Architecture: iphoneos-arm64
Maintainer: 551UK
Author: elias; GPS add-on by 551UK
Section: Tweaks
Depends: ws.hbang.common
Conflicts: uk.551.no2theft.gps
Replaces: uk.551.no2theft.gps
Description: No2Theft iOS 16 with working Gmail SMTP alert emails and experimental precise GPS map-link replacement. Dopamine rootless.
Icon: https://media.havoc.app/65dfc278aade10692ec51d5f
EOF
dpkg-deb --build -Zxz "$WORK/combined" "$OUTPUT"
echo "Built $OUTPUT"
echo "Install this as a replacement for the old Email Fix and separate GPS add-on; do not keep both package IDs installed."
