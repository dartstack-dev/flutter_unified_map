#!/usr/bin/env bash
# Regenerates the Pigeon bindings of both native packages from tool/pigeon/messages.dart.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCHEMA="$ROOT/tool/pigeon/messages.dart"

cd "$ROOT/packages/flutter_unified_map_android"
dart run pigeon --input "$SCHEMA" \
  --dart_out lib/src/messages.g.dart \
  --kotlin_out android/src/main/kotlin/dev/alphabyte/flutter_unified_map_android/Messages.g.kt \
  --kotlin_package dev.alphabyte.flutter_unified_map_android

cd "$ROOT/packages/flutter_unified_map_apple"
dart run pigeon --input "$SCHEMA" \
  --dart_out lib/src/messages.g.dart \
  --swift_out darwin/flutter_unified_map_apple/Sources/flutter_unified_map_apple/Messages.g.swift

cd "$ROOT"
dart format --line-length 120 packages/flutter_unified_map_android/lib/src/messages.g.dart packages/flutter_unified_map_apple/lib/src/messages.g.dart >/dev/null
echo "pigeon: generated"
