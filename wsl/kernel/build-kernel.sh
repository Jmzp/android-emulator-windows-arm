#!/usr/bin/env bash
# Builds a WSL2 arm64 kernel with binder enabled for Waydroid.
# Run inside the Ubuntu WSL distro (native arm64 build, no cross compiler).
#
#   ./build-kernel.sh [kernel-tag]
#
# Default tag matches the running WSL kernel (e.g. linux-msft-wsl-6.6.87.2).
# Output: $OUT_DIR/Image (default ~/wsl-kernel-build/Image)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNNING="$(uname -r | sed -E 's/^([0-9.]+).*/\1/')"
TAG="${1:-linux-msft-wsl-${RUNNING}}"
WORK_DIR="${WORK_DIR:-$HOME/wsl-kernel-build}"
SRC_DIR="$WORK_DIR/WSL2-Linux-Kernel"
OUT_DIR="${OUT_DIR:-$WORK_DIR}"

if [ "$(uname -m)" != "aarch64" ]; then
  echo "This script expects an arm64 WSL distro (got $(uname -m))." >&2
  exit 1
fi

echo "==> Installing build dependencies"
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  build-essential flex bison libssl-dev libelf-dev bc dwarves python3 cpio git

mkdir -p "$WORK_DIR"
if [ ! -d "$SRC_DIR/.git" ] || [ "$(git -C "$SRC_DIR" describe --tags 2>/dev/null)" != "$TAG" ]; then
  echo "==> Cloning $TAG"
  rm -rf "$SRC_DIR"
  git clone --depth 1 --branch "$TAG" \
    https://github.com/microsoft/WSL2-Linux-Kernel.git "$SRC_DIR"
fi

cd "$SRC_DIR"
echo "==> Configuring"
cp arch/arm64/configs/config-wsl-arm64 .config
scripts/kconfig/merge_config.sh -m .config "$SCRIPT_DIR/waydroid.config"
make olddefconfig

# merge_config only warns when a symbol doesn't stick; fail loudly instead.
for opt in ANDROID_BINDER_IPC ANDROID_BINDERFS PSI BRIDGE IP_NF_NAT IP_NF_MANGLE NETFILTER_XT_TARGET_CHECKSUM; do
  grep -q "^CONFIG_${opt}=y" .config || { echo "CONFIG_${opt} did not end up =y" >&2; exit 1; }
done

echo "==> Building Image with $(nproc) jobs (this takes a while)"
make -j"$(nproc)" Image

cp arch/arm64/boot/Image "$OUT_DIR/Image"
echo "==> Done: $OUT_DIR/Image ($(make -s kernelrelease))"
