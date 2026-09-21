#!/bin/zsh
# Prints the build identity for this checkout as two lines:
#   <build>   monotonic commit count on this branch (CFBundleVersion)
#   <commit>  short SHA, "-dirty" when the tree has changes (CargoCommit)
# The count alone is ambiguous across branches; the SHA settles it.
set -euo pipefail
cd "$(dirname "$0")/.."
build="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
commit="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then commit="$commit-dirty"; fi
print -- "$build"
print -- "$commit"
