#!/bin/sh
# Runs the tests. With only the Command Line Tools installed (no Xcode), SwiftPM can't find
# swift-testing on its own, so point it at the copy the CLT ships.
set -e
cd "$(dirname "$0")/.."
D=/Library/Developer/CommandLineTools/Library/Developer
if xcode-select -p | grep -q CommandLineTools; then
  exec swift test -Xswiftc -F$D/Frameworks -Xlinker -F$D/Frameworks \
    -Xlinker -rpath -Xlinker $D/Frameworks -Xlinker -rpath -Xlinker $D/usr/lib "$@"
fi
exec swift test "$@"
