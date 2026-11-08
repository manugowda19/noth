#!/bin/bash
# Full-system smoke test: unit harness, release build, bundle + signature, the
# required Info.plist permission strings, then launch the real app and confirm
# it stays up with no crash report. Exits non-zero on the first failure.
#
# This is the closest thing to an end-to-end test without XCUITest (which needs
# full Xcode). The notch UI itself (hover, HUDs, permission-gated features) is
# still verify-by-eye.
set -euo pipefail
cd "$(dirname "$0")/.."

pass() { echo "  ✓ $1"; }
fail() { echo "  ✗ $1"; exit 1; }

# Sign/replace can't touch a running bundle — stop any instance first.
pkill -x NotchFlow 2>/dev/null || true
sleep 1

echo "==> 1/5 unit harness"
# Capture output before grepping — piping a producer into `grep -q` makes grep
# close the pipe on match, which SIGPIPEs the producer and trips `pipefail`.
tests_out=$(./Scripts/run_tests.sh 2>&1 || true)
echo "$tests_out" | grep -q "All tests passed." \
    && pass "pure-model tests" || fail "unit tests"

echo "==> 2/5 release build + bundle"
./build.sh >/dev/null 2>&1 && [ -x Noth.app/Contents/MacOS/NotchFlow ] \
    && pass "Noth.app built" || fail "build/bundle"

echo "==> 3/5 signature"
sig_out=$(codesign -dvvv Noth.app 2>&1 || true)
echo "$sig_out" | grep -q "^Authority=NotchFlow" \
    && pass "signed Authority=NotchFlow (grants persist)" \
    || fail "not signed with the stable NotchFlow identity (ad-hoc?)"

echo "==> 4/5 Info.plist permission strings"
plist="Noth.app/Contents/Info.plist"
for key in NSCalendarsFullAccessUsageDescription NSRemindersFullAccessUsageDescription \
           NSAppleEventsUsageDescription NSLocationWhenInUseUsageDescription \
           NSCameraUsageDescription LSUIElement; do
    plutil -extract "$key" raw "$plist" >/dev/null 2>&1 \
        && pass "$key present" || fail "$key missing"
done

echo "==> 5/5 launch smoke"
before=$(ls -1 "$HOME/Library/Logs/DiagnosticReports/" 2>/dev/null | grep -c "^NotchFlow" || true)
pkill -x NotchFlow 2>/dev/null || true
sleep 1
open Noth.app
sleep 4
pgrep -x NotchFlow >/dev/null || fail "app is not running 4s after launch"
after=$(ls -1 "$HOME/Library/Logs/DiagnosticReports/" 2>/dev/null | grep -c "^NotchFlow" || true)
[ "$after" -le "$before" ] || fail "a new NotchFlow crash report appeared"
pass "app running, no new crash report"

echo "==> SMOKE TEST PASSED"
