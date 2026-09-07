#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <build directory>" >&2
  exit 2
fi

BUILD_DIR="$1"
JOBS="${CMAKE_BUILD_PARALLEL_LEVEL:-$(sysctl -n hw.ncpu)}"

ccache -p
ccache -s
ccache -z
cmake --build "$BUILD_DIR" --target build_final_bundle --parallel "$JOBS"
ccache -s
