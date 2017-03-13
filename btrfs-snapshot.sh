#!/usr/bin/env bash

# Dependency: btrfs
BTRFS=${BTRFS:-/sbin/btrfs}
if ! type $BTRFS >/dev/null 2>&1; then
    BTRFS=btrfs
    if ! type $BTRFS >/dev/null 2>&1; then
        echo "Dependency not found: btrfs" >&2
        exit 1
    fi
fi

# Dependency: stat
STAT=stat
if ! type $STAT >/dev/null 2>&1; then
    STAT=/usr/bin/stat
    if [ ! -x "$STAT" ]; then
        echo "Dependency not found: stat" >&2
        exit 1
    fi
fi

# Arguments
filesystem=$1
snap_name=$2
snap_count=$3

# Usage
if [ $# -eq 0 ]; then
    echo "Usage: $0 filesystem name count"
    echo ""
    echo "Arguments:"
    echo "  filesystem                       BTRFS filesystem/subvolume"
    echo "  name                             Snapshot base name (e.g., hourly)"
    echo "  count                            Number of snapshots to be kept"
    echo ""
    echo "Example cron jobs:"
    echo "  @hourly         $0 /data/Temp hourly 24"
    echo "  @midnight       $0 /data/Temp nightly 31"
    echo "  @monthly        $0 /data/Temp monthly 12"
    echo "  0 0 * * 1       $0 /data/Temp weekly 4"
    echo ""
    exit
fi

# Check argument: filesystem
if [ -z "$filesystem" ]; then
    echo -e "Missing argument: filesystem" >&2
    exit 1
fi
filesystem_inum=$($STAT --printf="%i" "$filesystem")
if [[ $? -ne 0 || -z "$filesystem_inum" ]]; then
    echo -e "Getting filesystem info failed!" >&2
    exit 1
fi
if [ $filesystem_inum -ne 256 ]; then
    echo -e "Not a BTRFS filesystem: $filesystem" >&2
    exit 1
fi

# Check argument: name
if [ -z "$snap_name" ]; then
    echo -e "Missing argument: name" >&2
    exit 1
elif ! [[ "$snap_name" =~ ^[a-z_0-9]+$ ]]; then
    echo -e "Invalid name: $snap_name" >&2
    exit 1
fi

# Check argument: count
if [ -z "$snap_count" ]; then
    echo -e "Missing argument: count" >&2
    exit 1
elif ! [[ "$snap_count" =~ ^[0-9]+$ ]]; then
    echo -e "Invalid count: $snap_count" >&2
    exit 1
elif [ $snap_count -eq 0 ]; then
    echo -e "Invalid count: $snap_count" >&2
    exit 1
fi

# Check for additional argument
if ! [ -z "$4" ]; then
    echo -e "Too many arguments" >&2
    exit 1
fi

# Set nullglob (don't handle '${snap_name}.*')
shopt -s nullglob

# Create snapshot root if necessary
snap_root="$filesystem/.snapshot"
if ! [ -d "$snap_root" ]; then
    echo -e "Creating snapshot root: $snap_root"
    mkdir "$snap_root"
    if [ $? -ne 0 ]; then
        echo -e "Creating snapshot root failed!" >&2
        exit 1
    fi
fi

# Index of last snapshot to be kept
snap_max=$(($snap_count - 1))

# List old snapshots
snap_names=()
for s in "${snap_root}/${snap_name}."*; do
    current_name="${s##*/}" # ${snap_name}.X
    current_suffix="${s##*.}" # X

    # Non-integer suffix
    if ! [[ "$current_suffix" =~ ^[0-9]+$ ]]; then
        # Ignore
        continue
    fi
    # Integer suffix

    # Delete oldest (or greater than max)
    # 25 should not be kept if max is 24 (25 would not be 25 units back)
    # Fails if $dingbat placed regular directory there
    if [ $current_suffix -ge $snap_max ]; then
        # $current_suffix is not a valid index
        $BTRFS subvolume delete \
            "${snap_root}/${snap_name}.${current_suffix}" >/dev/null
        if [ $? -ne 0 ]; then
            echo -e "Deleting snapshot failed!" >&2
            echo -e "${snap_name}.${current_suffix}" >&2
            exit 2
        fi
    else
        # $current_suffix is a valid index
        snap_names[$current_suffix]="$current_name"
    fi
done

# Move old snapshots
for ((i=$snap_max; i > 0; i--)); do
    new_index=$i
    ((old_index=new_index - 1))

    if [ -n "${snap_names[old_index]}" ]; then
        # Check type, don't move regular directory
        snap_inum=$($STAT --printf="%i" \
            "${snap_root}/${snap_name}.${old_index}")
        if [[ $? -ne 0 || -z "$snap_inum" ]]; then
            echo -e "Getting filesystem info failed!" >&2
            exit 2
        fi
        if [ $snap_inum -ne 256 ]; then
            echo -e "Not a BTRFS snapshot: ${snap_name}.${old_index}" >&2
            exit 2
        fi

        # Don't move into directory
        if [ -e "${snap_root}/${snap_name}.${new_index}" ]; then
            echo -e "New name already exists: ${snap_name}.${new_index}" >&2
            exit 2
        fi

        # Move snapshot
        mv \
            "${snap_root}/${snap_name}.${old_index}" \
            "${snap_root}/${snap_name}.${new_index}"
        if [ $? -ne 0 ]; then
            echo -e "Renaming snapshot failed!" >&2
            echo -e "${snap_name}.${old_index}" >&2
            exit 2
        fi
    fi
done

# Create snapshot
$BTRFS subvolume snapshot -r "$filesystem" \
    "${snap_root}/${snap_name}.0" >/dev/null
if [ $? -ne 0 ]; then
    echo -e "Creating snapshot failed!" >&2
    echo -e "${snap_name}.0" >&2
    exit 2
fi

