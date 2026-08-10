#!/usr/bin/env bash
#
# Builds the web app on Vercel, whose build image has no Flutter SDK.
#
# The SDK is downloaded into the build cache directory, so only the first
# build after a version bump pays the download cost; later builds reuse it.
#
# Required Vercel environment variables (Project → Settings → Environment
# Variables). All are public values — the anon/publishable key is protected by
# row-level security, and OAuth client ids are public by design. Never put the
# Supabase service-role key here.
#
#   SUPABASE_URL           https://<project-ref>.supabase.co
#   SUPABASE_ANON_KEY      the project's anon / publishable key
#   GOOGLE_WEB_CLIENT_ID   optional on web; needed for the Android build

set -euo pipefail

FLUTTER_VERSION="3.44.8"
CACHE_DIR="${VERCEL_CACHE_DIR:-.vercel/cache}"
FLUTTER_DIR="$CACHE_DIR/flutter-$FLUTTER_VERSION"

if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  echo "Downloading Flutter $FLUTTER_VERSION…"
  rm -rf "$FLUTTER_DIR"
  mkdir -p "$FLUTTER_DIR"
  curl -fsSL \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    | tar -xJ --strip-components=1 -C "$FLUTTER_DIR"
else
  echo "Reusing cached Flutter $FLUTTER_VERSION."
fi

export PATH="$FLUTTER_DIR/bin:$PATH"

# The SDK is unpacked, not cloned, so its git metadata is missing or stale.
# Flutter refuses to run without a valid repo; marking it safe and stamping the
# version keeps `flutter` from trying to self-update mid-build.
git config --global --add safe.directory "$(pwd)/$FLUTTER_DIR" || true

flutter config --no-analytics --no-cli-animations >/dev/null
flutter --version

flutter pub get

# Missing credentials are not fatal: the app detects it and runs offline-only
# rather than showing a sign-in button that cannot work. Warn loudly, though —
# it is almost always a forgotten environment variable.
if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_ANON_KEY:-}" ]; then
  echo "WARNING: SUPABASE_URL / SUPABASE_ANON_KEY are not set."
  echo "         Building without sync — the app will be offline-only."
fi

flutter build web \
  --release \
  --dart-define="SUPABASE_URL=${SUPABASE_URL:-}" \
  --dart-define="SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY:-}" \
  --dart-define="GOOGLE_WEB_CLIENT_ID=${GOOGLE_WEB_CLIENT_ID:-}"

echo "Built build/web"
