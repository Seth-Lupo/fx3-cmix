#!/bin/bash
# Idempotent bootstrap for a fx3-cmix work VM (Ubuntu 22.04).
# Usage: bash setup.sh   (run as the login user, uses sudo)
# Leaves: toolchain installed, repo at ~/fx3-cmix, enwik9 at /mnt/work/enwik9.
set -euo pipefail

echo "=== apt packages ==="
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  make git wget unzip upx-ucl time linux-tools-common "linux-tools-$(uname -r)" || \
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  make git wget unzip upx-ucl time linux-tools-generic

echo "=== clang-17 ==="
if ! command -v clang++-17 >/dev/null; then
  wget -q https://apt.llvm.org/llvm.sh -O /tmp/llvm.sh
  chmod +x /tmp/llvm.sh
  sudo /tmp/llvm.sh 17
  sudo apt-get install -y -qq llvm-17 # llvm-profdata-17 for PGO
fi
clang++-17 --version | head -1

echo "=== workspace on local temp SSD ==="
# D*ds_v4 VMs have a 150GB ephemeral SSD mounted at /mnt. Contents vanish on
# deallocate — only enwik9 (re-downloadable) and run artifacts live there.
sudo mkdir -p /mnt/work
sudo chown "$USER" /mnt/work

echo "=== repo ==="
if [ ! -d "$HOME/fx3-cmix" ]; then
  git clone https://github.com/Seth-Lupo/fx3-cmix "$HOME/fx3-cmix"
fi

echo "=== enwik9 ==="
if [ "${SKIP_ENWIK9:-0}" = "1" ]; then
  echo "skipped (SKIP_ENWIK9=1)"
elif [ ! -f /mnt/work/enwik9 ]; then
  wget -q --show-progress https://mattmahoney.net/dc/enwik9.zip -O /mnt/work/enwik9.zip
  unzip -o /mnt/work/enwik9.zip -d /mnt/work
  rm /mnt/work/enwik9.zip
fi
if [ -f /mnt/work/enwik9 ]; then md5sum /mnt/work/enwik9; fi   # expect e206c3450ac99950df65bf70ef61a12d

echo "=== done ==="
