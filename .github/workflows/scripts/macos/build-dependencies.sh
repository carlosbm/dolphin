#!/bin/bash

set -euo pipefail

export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-26.0}"
QT_DEPLOYMENT_TARGET="${QT_DEPLOYMENT_TARGET:-14.0}"
INSTALLDIR="${INSTALLDIR:-$HOME/deps}"
NPROCS="${NPROCS:-$(getconf _NPROCESSORS_ONLN)}"
BUILD_ROOT="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/primehack-deps.XXXXXX")"
DEPS_LOG_DIR="${DEPS_LOG_DIR:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/primehack-dependency-logs}"
QT=6.11.1

cleanup() {
  rm -rf "$BUILD_ROOT"
}
trap cleanup EXIT

mkdir -p "$INSTALLDIR"
mkdir -p "$DEPS_LOG_DIR"
exec > >(tee "$DEPS_LOG_DIR/build-dependencies.log") 2>&1
cd "$BUILD_ROOT"

export PKG_CONFIG_PATH="$INSTALLDIR/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export LDFLAGS="-L$INSTALLDIR/lib -dead_strip ${LDFLAGS:-}"
export CFLAGS="-I$INSTALLDIR/include -Os ${CFLAGS:-}"
export CXXFLAGS="-I$INSTALLDIR/include -Os ${CXXFLAGS:-}"

cat > SHASUMS <<EOF
d9594a31228aa23ad6b531719a29b45f0f3989fe6c136d45767ea179f233c1ac  qtbase-everywhere-src-$QT.tar.xz
7f3cf02f4824bf03c2c5859ea6db173bf1482a1daf24e6cdf7bc78cfa26a8a94  qtsvg-everywhere-src-$QT.tar.xz
8e61835a679c93fa9c6065b142353c2071ba68e297898937c32a03777fcaf50d  qttools-everywhere-src-$QT.tar.xz
37c02c81206594c7bb4edca85ac93e8e55a9836b70c960fde6cb0f8623ec5677  qttranslations-everywhere-src-$QT.tar.xz
EOF

curl --fail --location --retry 3 --retry-delay 2 \
  --remote-name "https://download.qt.io/archive/qt/${QT%.*}/$QT/submodules/qtbase-everywhere-src-$QT.tar.xz" \
  --remote-name "https://download.qt.io/archive/qt/${QT%.*}/$QT/submodules/qtsvg-everywhere-src-$QT.tar.xz" \
  --remote-name "https://download.qt.io/archive/qt/${QT%.*}/$QT/submodules/qttools-everywhere-src-$QT.tar.xz" \
  --remote-name "https://download.qt.io/archive/qt/${QT%.*}/$QT/submodules/qttranslations-everywhere-src-$QT.tar.xz"

shasum -a 256 --check SHASUMS

echo "Installing Qt Base..."
tar xf "qtbase-everywhere-src-$QT.tar.xz"
cd "qtbase-everywhere-src-$QT"
cmake -B build -G Ninja \
  -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$QT_DEPLOYMENT_TARGET" \
  -DCMAKE_PREFIX_PATH="$INSTALLDIR" \
  -DCMAKE_INSTALL_PREFIX="$INSTALLDIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DFEATURE_optimize_size=ON \
  -DFEATURE_dbus=OFF \
  -DFEATURE_framework=OFF \
  -DFEATURE_icu=OFF \
  -DFEATURE_opengl=OFF \
  -DFEATURE_printsupport=OFF \
  -DFEATURE_sql=OFF \
  -DFEATURE_gssapi=OFF \
  -DFEATURE_system_png=OFF \
  -DFEATURE_system_jpeg=OFF \
  -DCMAKE_MESSAGE_LOG_LEVEL=STATUS
cmake --build build --parallel "$NPROCS"
cmake --install build
cd ..

echo "Installing Qt SVG..."
tar xf "qtsvg-everywhere-src-$QT.tar.xz"
cd "qtsvg-everywhere-src-$QT"
cmake -B build -G Ninja \
  -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$QT_DEPLOYMENT_TARGET" \
  -DCMAKE_PREFIX_PATH="$INSTALLDIR" \
  -DCMAKE_INSTALL_PREFIX="$INSTALLDIR" \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel "$NPROCS"
cmake --install build
cd ..

echo "Installing Qt Tools..."
tar xf "qttools-everywhere-src-$QT.tar.xz"
cd "qttools-everywhere-src-$QT"
cmake -B build -G Ninja \
  -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$QT_DEPLOYMENT_TARGET" \
  -DCMAKE_PREFIX_PATH="$INSTALLDIR" \
  -DCMAKE_INSTALL_PREFIX="$INSTALLDIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DFEATURE_assistant=OFF \
  -DFEATURE_clang=OFF \
  -DFEATURE_distancefieldgenerator=OFF \
  -DFEATURE_designer=OFF \
  -DFEATURE_kmap2qmap=OFF \
  -DFEATURE_pixeltool=OFF \
  -DFEATURE_pkg_config=OFF \
  -DFEATURE_qev=OFF \
  -DFEATURE_qtattributionsscanner=OFF \
  -DFEATURE_qtdiag=OFF \
  -DFEATURE_qtplugininfo=OFF \
  -DFEATURE_qdoc=OFF
cmake --build build --parallel "$NPROCS"
cmake --install build
cd ..

echo "Installing Qt Translations..."
tar xf "qttranslations-everywhere-src-$QT.tar.xz"
cd "qttranslations-everywhere-src-$QT"
cmake -B build -G Ninja \
  -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$QT_DEPLOYMENT_TARGET" \
  -DCMAKE_PREFIX_PATH="$INSTALLDIR" \
  -DCMAKE_INSTALL_PREFIX="$INSTALLDIR" \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel "$NPROCS"
cmake --install build
cd ..

echo "Dependencies installed in $INSTALLDIR"
