#!/bin/bash

# Script: fstab-to-UUID.sh
# Description: Converts only /dev/sd* device paths in /etc/fstab to their corresponding UUID format.
# Strictly processes only standard SCSI/SATA disk devices (/dev/sd*) while preserving all other entries.
# This script can operate in dry-run mode to preview changes or write mode to apply them.
# The script creates a backup before making any changes to /etc/fstab.
# Usage: Run with --help for usage information

# Display usage and help information
show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Convert only standard SCSI/SATA disk device paths (/dev/sd*) in /etc/fstab to UUID format.
Only processes entries that begin with /dev/sd (e.g., /dev/sda1, /dev/sdb2).
All other device entries (including /dev/mapper/, /dev/disk/, etc.) will remain unchanged.

Options:
    -h, --help      Show this help message
    -w, --write     Write changes to /etc/fstab (requires root privileges)
    -d, --dry-run   Show what changes would be made without writing

Without any options, the script will run in dry-run mode.

Example:
    sudo $(basename "$0") --write    # Apply changes to /etc/fstab
    $(basename "$0") --dry-run       # Show potential changes
EOF
}

# Initialize default mode flags
WRITE_MODE=false
DRY_RUN=true

# Process command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -w|--write)
            WRITE_MODE=true
            DRY_RUN=false
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            WRITE_MODE=false
            shift
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Verify root privileges for write mode
if [ "$WRITE_MODE" = true ] && [ "$EUID" -ne 0 ]; then
    echo "Error: Write mode requires root privileges. Please run with sudo."
    exit 1
fi

# Create temporary working file
TEMP_FSTAB=$(mktemp)

# Main processing loop - read fstab line by line
while read -r line; do
    # Preserve comment lines unchanged
    if [[ "$line" =~ ^# ]]; then
        echo "$line" >> "$TEMP_FSTAB"
        continue
    fi

    # Extract first field (device path)
    device=$(echo "$line" | awk '{print $1}')

    # Only process /dev/sd* devices, preserve everything else
    if [[ "$device" =~ ^/dev/sd ]]; then
        # Get UUID for the device
        uuid=$(blkid -o value -s UUID "$device" 2>/dev/null)

        # Process the line - either replace device with UUID or keep unchanged
        if [ -n "$uuid" ]; then
            # Create new line with UUID
            new_line=$(echo "$line" | sed "s|$device|UUID=$uuid|")
            echo "$new_line" >> "$TEMP_FSTAB"
            
            # Show changes in dry-run mode
            if [ "$DRY_RUN" = true ]; then
                echo "Would change:"
                echo "- $line"
                echo "+ $new_line"
                echo
            fi
        else
            # Keep original line if no UUID found
            echo "$line" >> "$TEMP_FSTAB"
        fi
    else
        # Preserve all non-/dev/sd* entries unchanged
        echo "$line" >> "$TEMP_FSTAB"
    fi
done < /etc/fstab

# Apply or cleanup changes based on mode
if [ "$WRITE_MODE" = true ]; then
    # Backup and update fstab
    cp /etc/fstab /etc/fstab.bak
    mv "$TEMP_FSTAB" /etc/fstab
    echo "fstab has been updated with UUIDs. Backup saved as /etc/fstab.bak"
else
    # Cleanup in dry-run mode
    rm "$TEMP_FSTAB"
    if [ "$DRY_RUN" = true ]; then
        echo "Dry run completed. Use --write to apply changes."
    fi
fi