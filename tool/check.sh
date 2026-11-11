#!/usr/bin/env bash
#
# Runs the CI checks that fail most often, locally and in one command: the
# analyzer, and the Linux job's "Verify generated sources are current" step.
# A stale Riverpod or Drift `.g.dart` builds and passes every test, so it is
# only caught by regenerating and diffing -- which is what this does, exactly as
# .github/workflows/ci.yml does it.
#
# Needs a clean tracked tree: the diff cannot tell generated changes from your
# own uncommitted ones. Tests are not run here; `flutter test` covers them.
#
# To run it before every push (not installed automatically):
#   printf '#!/bin/sh\nexec tool/check.sh\n' > .git/hooks/pre-push
#   chmod +x .git/hooks/pre-push
#
# Usage:
#   tool/check.sh

set -euo pipefail

cd "$(dirname "$0")/.."

if ! git diff --quiet HEAD; then
  echo 'Uncommitted changes to tracked files; commit or stash them first.' >&2
  exit 1
fi

echo '==> dart analyze'
dart analyze

echo '==> dart run build_runner build'
dart run build_runner build

if ! git diff --exit-code; then
  echo 'Generated sources were stale; commit the changes above.' >&2
  exit 1
fi

echo '==> All checks passed.'
