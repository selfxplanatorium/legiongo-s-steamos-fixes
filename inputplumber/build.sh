#!/usr/bin/env bash
# Build the patched InputPlumber in a container.
# Usage: inputplumber/build.sh [inputplumber-tag]   (default: v0.83.1)
# Output: dist/inputplumber
set -euo pipefail
TAG=${1:-v0.83.1}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$HERE")
WORK=$ROOT/build
PATCH=$HERE/0001-legion-go-s-touchpad-from-gamepad-report.patch
IMAGE=legion-go-s-ip-builder:1.92

command -v docker >/dev/null || { echo "docker is required" >&2; exit 1; }
mkdir -p "$WORK" "$ROOT/dist"

if [[ ! -d "$WORK/InputPlumber/.git" ]]; then
    git clone --depth 1 --branch "$TAG" https://github.com/ShadowBlip/InputPlumber.git "$WORK/InputPlumber"
fi
cd "$WORK/InputPlumber"
git checkout -q -- .
git apply --check "$PATCH"
git apply "$PATCH"

docker build -t "$IMAGE" "$HERE"
mkdir -p "$WORK/cargo-home"
docker run --rm \
    -v "$WORK/InputPlumber:/src" -v "$WORK/cargo-home:/home/build" -w /src \
    -e HOME=/home/build -e CARGO_HOME=/home/build/.cargo \
    --user "$(id -u):$(id -g)" "$IMAGE" \
    cargo build --release --locked --target x86_64-unknown-linux-gnu

install -m 755 target/x86_64-unknown-linux-gnu/release/inputplumber "$ROOT/dist/inputplumber"
git checkout -q -- .
echo "built $ROOT/dist/inputplumber ($("$ROOT/dist/inputplumber" --version))"
