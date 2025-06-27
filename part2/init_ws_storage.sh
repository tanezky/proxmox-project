#!/usr/bin/env bash
set -e

# Variables
LUKS_DEVICE="/dev/sda"
MAPPER_NAME="samsungfit"
MOUNT_POINT="/media/samsungfit"
NON_ROOT_USER=""

# Check if the device is already mounted
if grep -qs "$MOUNT_POINT" /proc/mounts; then
  echo "Workspace storage is already mounted."
  read -p "Do you want to unmount it? (y/N) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Unmounting workspace storage"
    umount "$MOUNT_POINT"
    cryptsetup close "/dev/mapper/$MAPPER_NAME"
    echo "done"
  else
    echo "Unmount operation canceled."
  fi
else
  # Open LUKS device if not already open
  if [ ! -e "/dev/mapper/$MAPPER_NAME" ]; then
    echo "Opening LUKS device"
    cryptsetup luksOpen "$LUKS_DEVICE" "$MAPPER_NAME"
  fi    
  
  echo "Mounting workspace storage"
  mount -m "/dev/mapper/$MAPPER_NAME" "$MOUNT_POINT"

  # Fix permissions to non-root user when using VSCode remotely, will not run if user not set in variables
  if [ -z "$NON_ROOT_USER" ]; then
    echo "Non-root user is not set, skipping permission change."
  else
    echo "Changing ownership of $MOUNT_POINT to $NON_ROOT_USER"
    chown -R "$NON_ROOT_USER" "$MOUNT_POINT"
  fi
  echo "done"
fi
