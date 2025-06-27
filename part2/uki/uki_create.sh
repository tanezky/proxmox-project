#!/usr/bin/env bash

# This script generates a signed Unified Kernel Image (UKI) for Proxmox VE
# for use with Secure Boot.
#
# This script is inspired by https://wiki.debian.org/EFIStub
# It automatically finds the latest kernel and does not require gawk.
#
# Requirements:
# - systemd-boot-efi (for EFISTUB)
# - sbsigntool (for signing the UKI)


# Strict mode: exit on error, exit on unset variable, and fail on pipe errors.
set -euo pipefail

#
# Configuration

# Directory where this script is located. Used for relative paths.
WORKDIR="$(dirname "$(readlink -f "$0")")"
readonly WORKDIR

#
# Kernel cmdline to be concatenated after root=UUID...
# When updating cmdline parameters, remove existing cmdline file before running this script.
readonly KERNEL_CMDLINE=" ro quiet splash"

#
# Paths for UKI components
readonly EFISTUB="/usr/lib/systemd/boot/efi/linuxx64.efi.stub"
readonly OSRELEASE="/usr/lib/os-release"
readonly CMDLINE_FILE="${WORKDIR}/cmdline"
readonly SPLASH_IMG="${WORKDIR}/splash.bmp"

#
# Signing Configuration
readonly SB_KEY_FILE="${WORKDIR}/../sb/keys/db.key"
readonly SB_CERT_FILE="${WORKDIR}/../sb/certs/db.crt"

#
# Output Configuration
readonly BOOT_DIR="/boot/efi/EFI/pve"
readonly FINAL_EFI_NAME="pve-uki.efi"


#
# Functions

# Print a message to stdout.
msg() {
    printf '%s\n' "$@"
}

# Print an error message to stderr and exit.
die() {
    printf 'Error: %s\n' "$@" >&2
    exit 1
}

# Calculates the aligned offset for a new section.
# Usage: align_offset <base_offset> <previous_file_path>
# Returns the new aligned offset.
align_offset() {
    local base_offset="$1"
    local prev_file="$2"
    local file_size
    local new_offset

    file_size=$(stat -Lc%s "$prev_file")
    new_offset=$((base_offset + file_size))
    # Align to the next boundary, using the global 'align' variable
    new_offset=$((new_offset + align - new_offset % align))
    printf '%s' "$new_offset"
}


#
# Checks

# Check for root privileges, required for the final copy step.
if [[ "$(id -u)" -ne 0 ]]; then
    die "This script must be run as root."
fi

# Create a temporary directory for temp files and set a trap to clean it up.
TMPDIR=$(mktemp -d)
readonly TMPDIR
trap 'rm -rf -- "$TMPDIR"' EXIT

msg "Working directory: $WORKDIR"
msg "Temporary directory: $TMPDIR"

# Find the latest Proxmox kernel
latest_kernel_path=$(find /boot/ -maxdepth 1 -type f -name 'vmlinuz-*' | sort -V | tail -n1)
if [[ -z "$latest_kernel_path" ]]; then
    die "Could not find a Proxmox kernel in /boot/."
fi

# Extract the version string from the full path.
latest_kernel_ver=$(basename "$latest_kernel_path" | sed 's/^vmlinuz-//')

msg "Latest kernel version found: $latest_kernel_ver"

# Define final component paths. KERNEL_IMG uses the direct path found.
# INITRD_IMG is constructed from the version and points to /boot/.
readonly KERNEL_IMG="$latest_kernel_path"
readonly INITRD_IMG="/boot/initrd.img-${latest_kernel_ver}"
readonly UNSIGNED_EFI="${TMPDIR}/pve-uki-unsigned.efi"
readonly SIGNED_EFI="${WORKDIR}/${FINAL_EFI_NAME}"

# Verify that all required source files exist.
for f in "$EFISTUB" "$OSRELEASE" "$SPLASH_IMG" "$KERNEL_IMG" "$INITRD_IMG"; do
    if [[ ! -f "$f" ]]; then
        die "Required file not found: $f"
    fi
done

# Verify that all required dependencies exist.
for tool in "objcopy" "objdump" "stat" "sbsign"; do
    if ! command -v "$tool" &> /dev/null; then
        die "Required command not found: '$tool'. Please install it."
    fi
done

# Generate kernel command line file if it doesn't exist.
if [[ ! -f "$CMDLINE_FILE" ]]; then
    msg "No cmdline file found, creating one at '$CMDLINE_FILE'..."
    # Get root filesystem from current boot options.
    root_fs=$(awk '{for(i=1;i<=NF;i++) if($i ~ /^root=/) print $i}' /proc/cmdline)
    if [[ -z "$root_fs" ]]; then
        die "Could not determine root filesystem from /proc/cmdline."
    fi
    # Concatenate other cmdline parameters and create the cmdline file.
    printf "%s $KERNEL_CMDLINE" "$root_fs" > "$CMDLINE_FILE"
fi

#
# Main Logic

msg "Calculating section offsets..."

# Get section alignment from the EFI stub. Convert hex to decimal.
align_hex=$(objdump -p "$EFISTUB" | awk '/SectionAlignment/ {print $2}')
readonly align=$((16#$align_hex))

# Get the end address of the last section in the stub.
# awk prints the hex offset and size of the last section it finds.
# The shell then performs the arithmetic.
read -r last_offset_hex last_size_hex < <(objdump -h "$EFISTUB" | awk 'NF==7 {offset=$4; size=$3} END {print offset, size}')
last_section_end=$(( 0x$last_offset_hex + 0x$last_size_hex ))

# The .osrel section starts at the next aligned offset after the stub's sections.
osrel_offs=$((last_section_end + align - last_section_end % align))

# Calculate subsequent offsets based on the size of the preceding file, with alignment.
cmdline_offs=$(align_offset "$osrel_offs" "$OSRELEASE")
splash_offs=$(align_offset "$cmdline_offs" "$CMDLINE_FILE")
initrd_offs=$(align_offset "$splash_offs" "$SPLASH_IMG")
linux_offs=$(align_offset "$initrd_offs" "$INITRD_IMG")

msg "Creating the unsigned UKI..."

objcopy \
    --add-section .osrel="$OSRELEASE" --change-section-vma .osrel="$(printf '0x%x' "$osrel_offs")" \
    --add-section .cmdline="$CMDLINE_FILE" --change-section-vma .cmdline="$(printf '0x%x' "$cmdline_offs")" \
    --add-section .splash="$SPLASH_IMG" --change-section-vma .splash="$(printf '0x%x' "$splash_offs")" \
    --add-section .initrd="$INITRD_IMG" --change-section-vma .initrd="$(printf '0x%x' "$initrd_offs")" \
    --add-section .linux="$KERNEL_IMG" --change-section-vma .linux="$(printf '0x%x' "$linux_offs")" \
    "$EFISTUB" "$UNSIGNED_EFI"

msg "Unsigned UKI created at $UNSIGNED_EFI"

msg "Signing the UKI..."
if [[ ! -f "$SB_KEY_FILE" || ! -f "$SB_CERT_FILE" ]]; then
    die "Signing key '$SB_KEY_FILE' or certificate '$SB_CERT_FILE' not found."
fi

# Signing the UKI
msg ""
msg "ENTER THE PASSWORD FOR THE SIGNING KEY '$SB_KEY_FILE':"
sbsign --key "$SB_KEY_FILE" --cert "$SB_CERT_FILE" --output "$SIGNED_EFI" "$UNSIGNED_EFI"

msg "Signed UKI created at $SIGNED_EFI"

msg "Copying signed UKI to boot directory..."
mkdir -p "$BOOT_DIR"
cp "$SIGNED_EFI" "${BOOT_DIR}/${FINAL_EFI_NAME}"

msg "Successfully created, signed and deployed UKI to ${BOOT_DIR}/${FINAL_EFI_NAME}"
