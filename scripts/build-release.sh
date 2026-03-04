#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# build-release.sh — Build a signed Flutter release APK/AAB for SudVet
#
# Prerequisites:
#   1. android/key.properties must exist (copy from android/key.properties.example)
#   2. The keystore file referenced in key.properties must exist
#   3. Set the three env vars below before running:
#
#        export API_URL=https://your-api-domain.com
#        export MOBILE_API_URL=https://your-mobile-api-domain.com
#        export GOOGLE_CLIENT_ID=xxxx.apps.googleusercontent.com
#
# Usage:
#   chmod +x scripts/build-release.sh
#   ./scripts/build-release.sh          # builds AAB (Play Store)
#   ./scripts/build-release.sh apk      # builds split APKs (sideload / testing)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Validate required env vars ────────────────────────────────────────────────
: "${API_URL:?Set API_URL to your ops_api HTTPS URL, e.g. https://api.yourdomain.com}"
: "${MOBILE_API_URL:?Set MOBILE_API_URL to your mobile_api HTTPS URL}"
: "${GOOGLE_CLIENT_ID:?Set GOOGLE_CLIENT_ID from Google Cloud Console}"

# ── Validate signing prerequisites ───────────────────────────────────────────
KEY_PROPS="android/key.properties"
if [[ ! -f "$KEY_PROPS" ]]; then
  echo "ERROR: $KEY_PROPS not found."
  echo "       Copy android/key.properties.example → android/key.properties and fill it in."
  exit 1
fi

# ── Common dart-define flags ──────────────────────────────────────────────────
DEFINES=(
  "--dart-define=SUDVET_API_BASE_URL=${API_URL}"
  "--dart-define=SUDVET_MOBILE_API_URL=${MOBILE_API_URL}"
  "--dart-define=GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID}"
  "--dart-define=GOOGLE_SERVER_CLIENT_ID=${GOOGLE_CLIENT_ID}"
)

# ── Build ─────────────────────────────────────────────────────────────────────
flutter pub get

if [[ "${1:-aab}" == "apk" ]]; then
  echo ">>> Building release APKs (split by ABI)..."
  flutter build apk --release --split-per-abi "${DEFINES[@]}"
  echo ""
  echo "APKs written to:"
  find build/app/outputs/flutter-apk -name "*.apk" | sort
else
  echo ">>> Building release AAB (Android App Bundle for Play Store)..."
  flutter build appbundle --release "${DEFINES[@]}"
  echo ""
  echo "AAB written to:"
  find build/app/outputs/bundle/release -name "*.aab" | sort
fi

echo ""
echo "Done. Upload the AAB/APK to Google Play Console."
