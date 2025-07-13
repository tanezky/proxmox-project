#!/bin/env bash
#
# Copies initramfs files to system locations

# Strict mode: exit on error, exit on unset variable, and fail on pipe errors.
set -euo pipefail

#
# Configuration

# Directory where this script is located. Used for relative paths.
WORKDIR="$(dirname "$(readlink -f "$0")")"
readonly WORKDIR

# The hook script is used to copy the necessary TPM tools into the initramfs image.
echo "Copy Initramfs HOOK"
if ! install -o root -g root -m 744 \
  "${WORKDIR}/tpm_tools_hook.sh" /etc/initramfs-tools/hooks/tpm_tools_hook.sh; then
    echo "Failed to copy tpm_tools_hook.sh"
    exit 1
fi

# This script extends a PCR with a random value once the rootfs is mounted.
echo "Copy tpm_pcrextend script"
if ! install -o root -g root -m 744 \
  "${WORKDIR}/tpm_pcrextend.sh" /etc/initramfs-tools/scripts/local-bottom/tpm_pcrextend.sh; then
    echo "Failed to copy tpm_pcrextend.sh"
    exit 1
fi

# Copy tpm_unseal script
# This script unseals a TPM2 sealed LUKS key using the TPM2 tool, this is run by crypttab
if ! install -o root -g root -m 744 \
  "${WORKDIR}/tpm_unseal.sh" /lib/cryptsetup/scripts/tpm_unseal.sh; then
    echo "Failed to copy tpm_unseal.sh"
    exit 1
fi

echo "--- Completed copying files, update initramfs to include in initrd ---"