#!/bin/sh
#
# Includes TPM2 tools in the initramfs image.
#   tpm2_unseal is used to unseal a TPM2 sealed LUKS key.
#   tpm2_pcrextend is used to extend PCR with a random value.
#   tpm2_getrandom is used to generate random values for PCR extension.

PREREQ=""
prereqs() { echo "$PREREQ"; }
case "$1" in
    prereqs) prereqs; exit 0;;
esac
. /usr/share/initramfs-tools/hook-functions

#
# Copy necessary tpm2 tools into initrd.
copy_exec /usr/bin/tpm2_unseal /usr/bin
copy_exec /usr/bin/tpm2_pcrextend /usr/bin
copy_exec /usr/bin/tpm2_getrandom /usr/bin

#
# Add the TCTI device driver, needed by tpm2 tools to be able to communicate with TPM

# 1. Create the destination directory inside the initramfs image
mkdir -p ${DESTDIR}/usr/lib/x86_64-linux-gnu/

# 2. Copy the driver library file
cp /usr/lib/x86_64-linux-gnu/libtss2-tcti-device.so.0.0.0 ${DESTDIR}/usr/lib/x86_64-linux-gnu/

# 3. Create the symbolic link that ldconfig expects (fixes the warning about broken symlink)
ln -sf libtss2-tcti-device.so.0.0.0 ${DESTDIR}/usr/lib/x86_64-linux-gnu/libtss2-tcti-device.so.0
