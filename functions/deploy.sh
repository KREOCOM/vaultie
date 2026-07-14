#!/usr/bin/env bash
#
# Deploy Vaultie Cloud Functions AND restore finish_bank_auth's timeout/memory.
# Run this INSTEAD of a bare `firebase deploy` for the functions.
#
# WHY THIS EXISTS
#   firebase-tools 15.x Python discovery does NOT apply the
#   @on_call(timeout_sec=300, memory=MB_512) decorator on finish_bank_auth — every
#   `firebase deploy` silently resets the Cloud Run service back to 60s / 256Mi.
#   A cold-start 12-month scan then hits DEADLINE_EXCEEDED. This script re-applies
#   300s / 512Mi via `gcloud run services update`, which (unlike a Cloud Run
#   console "deploy new revision") KEEPS the mounted secrets.
#
#   Until firebase-tools fixes the discovery bug, ALWAYS deploy with this script.
#
# ONE-TIME SETUP (only if gcloud is missing):
#   brew install --cask google-cloud-sdk
#   gcloud auth login
#   gcloud config set project vaultie-1a2c4
#
set -euo pipefail

REGION="europe-west1"
SERVICE="finish-bank-auth"   # Cloud Run service name = function name, _ → -
# pyexpat on macOS 26 is broken; point at Homebrew's expat so discovery runs.
EXPAT="/opt/homebrew/opt/expat/lib"

cd "$(dirname "$0")/.."   # repo root (firebase.json lives here)

# ── SAFETY: the 53MB merchant index is gitignored (not in version control), so a
# clean checkout / CI / another machine can be missing it. Without it the resolver
# SILENTLY degrades to the tiny KB → merchants stop being recognised for everyone,
# with no error. Refuse to deploy unless the index is present and a sane size, so
# a broken index can never ship unnoticed.
INDEX="functions/kb/merchant_index.sqlite"
MIN_MB=40
if [[ ! -f "$INDEX" ]]; then
  echo "✗ ABORT: merchant index missing: $INDEX"
  echo "  Rebuild it before deploying:  python3 tools/kb_build/build_index.py"
  exit 1
fi
SIZE_MB=$(( $(stat -f%z "$INDEX" 2>/dev/null || stat -c%s "$INDEX") / 1048576 ))
if (( SIZE_MB < MIN_MB )); then
  echo "✗ ABORT: merchant index too small (${SIZE_MB}MB < ${MIN_MB}MB) — likely truncated/corrupt: $INDEX"
  echo "  Rebuild it:  python3 tools/kb_build/build_index.py"
  exit 1
fi
echo "✓ Merchant index present (${SIZE_MB}MB) — merchant recognition will ship."

echo "▶ Deploying Cloud Functions…"
DYLD_LIBRARY_PATH="$EXPAT" firebase deploy --only functions

echo
echo "▶ Restoring $SERVICE timeout=300s / memory=512Mi (firebase-tools resets these)…"
if command -v gcloud >/dev/null 2>&1; then
  gcloud run services update "$SERVICE" \
    --region="$REGION" --timeout=300 --memory=512Mi
  echo "✓ $SERVICE → 300s / 512Mi (mounted secrets preserved)."
  echo "  You can now raise the client's monthsBack back to 12 if desired."
else
  echo "⚠ gcloud is NOT installed — timeout/memory were NOT restored."
  echo "  The function is still at 60s / 256Mi (keep monthsBack=6)."
  echo "  Install once, then re-run this script:"
  echo "    brew install --cask google-cloud-sdk && gcloud auth login"
  echo "  Or apply manually:"
  echo "    gcloud run services update $SERVICE --region=$REGION --timeout=300 --memory=512Mi"
  exit 1
fi
