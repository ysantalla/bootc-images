#!/usr/bin/env bash
# Builds the infrared camera's driver, unsigned: hm1092.sh <kernel> <output file>
# For a throwaway container: it installs a compiler. CI runs it in module.yml, signs the result
# in a job of its own, and build.sh installs it.
set -euo pipefail
kernel=$1 out=$2
src=$(dirname "$(readlink -f "$0")")/hm1092
version=${kernel%%-*} arch=${kernel##*.} rest=${kernel#*-}
release=${rest%."$arch"}
fedora=${release##*.fc}

dnf5 -y install gcc make elfutils-libelf-devel kmod gnupg2 curl
# Fedora's repositories only keep the newest kernel, and the image can be one behind.
# Koji keeps signed copies, in a directory named after the end of the key's fingerprint.
if ! dnf5 -y install "kernel-devel-$kernel"; then
  key=/usr/share/pki/rpm-gpg/RPM-GPG-KEY-fedora-$fedora-$arch
  fingerprint=$(gpg --show-keys --with-colons "$key" | awk -F: '$1 == "fpr" { print tolower($10); exit }')
  rpm=/tmp/kernel-devel-$kernel.rpm
  curl -fL --retry 3 -o "$rpm" \
    "https://kojipkgs.fedoraproject.org/packages/kernel/$version/$release/data/signed/${fingerprint: -8}/$arch/kernel-devel-$kernel.rpm"
  rpmkeys --import "$key"
  # An unsigned package also passes --checksig, so the signature has to be named
  rpmkeys --checksig --verbose "$rpm" | tee /tmp/checksig
  grep -qiE "signature.*${fingerprint: -8}.*: OK" /tmp/checksig
  dnf5 -y install "$rpm"
fi

build=$(mktemp -d)
cp "$src/hm1092.c" "$src/Makefile" "$build/"
make -C "/usr/src/kernels/$kernel" M="$build" modules
strip --strip-debug "$build/hm1092.ko"
[[ "$(modinfo -F vermagic "$build/hm1092.ko" | cut -d' ' -f1)" == "$kernel" ]]
install -Dm0644 "$build/hm1092.ko" "$out"
