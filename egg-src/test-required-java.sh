#!/bin/bash
# Self-check for start.sh's required_java_for() — the game-version -> Java-version
# mapping that decides which JVM args (and which yolks image) a build needs.
# Must stay in step with getRequiredJavaVersion() in the launcher's electron/java.ts.
#
# Usage: ./egg-src/test-required-java.sh
set -uo pipefail

cd "$(dirname "$0")"
# shellcheck disable=SC1090
eval "$(sed -n '/^required_java_for() {/,/^}/p' start.sh)"

fail=0
check() {
  local got
  got="$(required_java_for "$1" || echo UNKNOWN)"
  if [ "$got" != "$2" ]; then
    printf 'MISMATCH %-14s got %-7s want %s\n' "$1" "$got" "$2"
    fail=1
  fi
}

# >= 0.4.6 (current counter scheme) -> Java 25
check 0.4.6 25; check 0.4.6-rc1 25; check 0.4.12 25; check 0.5.0 25; check 0.10.0 25
check 1.0.0 25; check 2.3.4 25

# 0.3 .. 0.4.5 -> Java 21 (both schemes)
check 0.4.0 21; check 0.4.5 21; check 0.3 21; check 0.300.0 21; check 0.302.101 21
check 0.400.307 21

# < 0.3, legacy decimal minors -> Java 8
check 0.2 8; check 0.17 8; check 0.163 8; check 0.1801 8; check 0.19624 8; check 0.203.175 8

# Unreadable version strings must not pick a Java version at all
check "" UNKNOWN; check legacy UNKNOWN; check 0 UNKNOWN; check 0.x.1 UNKNOWN

[ "$fail" -eq 0 ] && echo "required_java_for: all cases OK"
exit "$fail"
