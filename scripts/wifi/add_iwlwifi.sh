#!/bin/bash
# Build and package Intel iwlwifi backport driver (e.g. BE200) for FriendlyWrt.
# Branch can be overridden via IWLWIFI_BRANCH (default: release/core98).
set -eu

top_path=$(pwd)
branch="${IWLWIFI_BRANCH:-release/core98}"

# Prepare toolchain and kernel info
export PATH=/opt/FriendlyARM/toolchain/11.3-aarch64/bin:$PATH
pushd kernel >/dev/null
kernel_ver=$(make CROSS_COMPILE=aarch64-linux-gnu- ARCH=arm64 kernelrelease)
popd >/dev/null

modules_dir=$(readlink -f ./out/output_*_kmodules/lib/modules/${kernel_ver})
[ -d "${modules_dir}" ] || {
	echo "please build kernel first."
	exit 1
}

# Clone backport-iwlwifi
rm -rf backport-iwlwifi
git clone --depth=1 -b "${branch}" https://git.kernel.org/pub/scm/linux/kernel/git/iwlwifi/backport-iwlwifi.git

# Build driver modules
(cd backport-iwlwifi && {
	make CROSS_COMPILE=aarch64-linux-gnu- ARCH=arm64 -C "${top_path}/kernel" M=$(pwd)
	cp *.ko "${modules_dir}/" -afv
})

# Prepare firmware and autoload config for rootfs overlay
overlay_dir="${top_path}/iwlwifi-files"
firmware_dst="${overlay_dir}/lib/firmware"
config_dir="${overlay_dir}/etc/modules.d"
mkdir -p "${firmware_dst}" "${config_dir}"

# Copy firmware if provided locally (put files under scripts/wifi/firmware/iwlwifi/)
firmware_src="${top_path}/scripts/wifi/firmware/iwlwifi"
if compgen -G "${firmware_src}/iwlwifi-*.ucode" >/dev/null || compgen -G "${firmware_src}/*.pnvm" >/dev/null; then
	cp ${firmware_src}/iwlwifi-*.ucode "${firmware_dst}/" 2>/dev/null || true
	cp ${firmware_src}/*.pnvm "${firmware_dst}/" 2>/dev/null || true
else
	echo "WARNING: No firmware found in ${firmware_src}, please place iwlwifi-*.ucode / *.pnvm here."
fi

# Autoload modules on boot
cat > "${config_dir}/10-iwlwifi" <<EOF
iwlwifi
iwlmvm
EOF

# Add overlay to build output
if ! grep -q iwlwifi-files .current_config.mk; then
	echo "FRIENDLYWRT_FILES+=(iwlwifi-files)" >> .current_config.mk
fi

