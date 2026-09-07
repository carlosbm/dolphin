#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <build directory>" >&2
  exit 2
fi

BUILD_DIR="$1"
JOBS="${CMAKE_BUILD_PARALLEL_LEVEL:-$(sysctl -n hw.ncpu)}"

cmake --build "$BUILD_DIR" --target tests --parallel "$JOBS"
ctest --test-dir "$BUILD_DIR" --output-on-failure --tests-regex '^tests$'
