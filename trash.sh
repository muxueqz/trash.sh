#!/bin/bash
#
# trash.sh — Move files to a .trash directory on the same partition
# Example:
#   ./trash.sh /data/myfile.txt
#     → moves it to /data/.trash/myfile.txt-2025-10-31_12-00-00
#
#   ./trash.sh -c
#     → clears all .trash folders on all mounted partitions
#
#   ./trash.sh -c /data
#     → clears only /data/.trash

# Generate a timestamp for unique naming
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

# --- Function: get mount point of a given file/path ---
get_mount_point() {
    df --output=target "$1" 2>/dev/null | tail -1
}

# --- Function: get .trash directory path of a given file ---
get_trash_dir() {
    local FILE="$1"
    local MOUNT_POINT
    MOUNT_POINT=$(get_mount_point "$FILE")
    echo "$MOUNT_POINT/.trash"
}

# --- Function: create .trash directory with same ownership/permissions as mount root ---
create_trash_dir() {
    local TRASH_DIR="$1"
    local MOUNT_POINT
    MOUNT_POINT=$(dirname "$TRASH_DIR")

    if [ ! -d "$TRASH_DIR" ]; then
        mkdir -p "$TRASH_DIR"
        # Inherit ownership and permissions from the mount point root
        OWNER=$(stat -c "%u" "$MOUNT_POINT")
        GROUP=$(stat -c "%g" "$MOUNT_POINT")
        PERMS=$(stat -c "%a" "$MOUNT_POINT")
        chown "$OWNER:$GROUP" "$TRASH_DIR"
        chmod "$PERMS" "$TRASH_DIR"
    fi
}

# --- CLEAR ALL .trash DIRECTORIES ---
if [ "$1" == "-c" ]; then
    TARGET_PATH="$2"

    # Clear all partitions if no argument is given
    if [ -z "$TARGET_PATH" ]; then
        echo "Searching for .trash folders on all mounted partitions..."
        TRASH_DIRS=$(find $(mount | awk '{print $3}') -maxdepth 1 -type d -name ".trash" 2>/dev/null)

        if [ -z "$TRASH_DIRS" ]; then
            echo "No .trash folders found."
            exit 0
        fi

        echo "The following .trash folders will be cleared:"
        echo "$TRASH_DIRS"
        echo -n "Are you sure you want to clear ALL of them? [Y/N]: "
        read -r CONFIRM
        if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
            for DIR in $TRASH_DIRS; do
                echo "Clearing $DIR ..."
                /bin/rm -rf "${DIR:?}/"*
            done
            echo "All trash folders cleared."
        else
            echo "Operation cancelled."
        fi
        exit 0
    fi

    # Clear only the partition of the provided path
    MOUNT_POINT=$(get_mount_point "$TARGET_PATH")
    TRASH_DIR="$MOUNT_POINT/.trash"

    if [ ! -d "$TRASH_DIR" ]; then
        echo "No trash directory found at $TRASH_DIR."
        exit 0
    fi

    FILE_COUNT=$(find "$TRASH_DIR" -type f | wc -l)
    DIR_COUNT=$(find "$TRASH_DIR" -type d | wc -l)
    TOTAL_SIZE=$(du -sh "$TRASH_DIR" | cut -f1)
    ((DIR_COUNT--))

    echo "Trash location: $TRASH_DIR"
    echo "$FILE_COUNT files"
    echo "$DIR_COUNT directories"
    echo "Total size: $TOTAL_SIZE"

    echo -n "Are you sure you want to clear this trash? [Y/N]: "
    read -r CONFIRM
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        /bin/rm -rf "$TRASH_DIR"/*
        echo "Trash cleared: $TRASH_DIR"
    else
        echo "Operation cancelled."
    fi
    exit 0
fi

# --- MOVE FILES TO .trash ---

# Check for files
if [ $# -eq 0 ]; then
    echo "No files or directories provided."
    exit 1
fi

# Display files that will be trashed
echo "Files and directories to be moved to trash:"
for FILE in "$@"; do
    if [ -e "$FILE" ]; then
        echo "$FILE"
    else
        echo "Warning: $FILE does not exist."
        exit 1
    fi
done

# Confirm move
echo -n "Are you sure you want to move these items to their respective trash folders? [Y/N]: "
read -r CONFIRM_MOVE
if [[ ! "$CONFIRM_MOVE" =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 0
fi

# Move each file to its partition's .trash
for FILE in "$@"; do
    if [ -e "$FILE" ]; then
        BASENAME=$(basename "$FILE")
        TRASH_DIR=$(get_trash_dir "$FILE")

        create_trash_dir "$TRASH_DIR"

        DEST="$TRASH_DIR/$BASENAME-$TIMESTAMP"

        mv "$FILE" "$DEST"
        if [ $? -eq 0 ]; then
            echo "Moved '$FILE' -> '$DEST'"
        else
            echo "Error moving '$FILE'"
        fi
    else
        echo "Warning: $FILE does not exist."
    fi
done
