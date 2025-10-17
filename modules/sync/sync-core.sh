#!/bin/bash

# Core Sync Module
# Provides the main sync_item function with file/directory detection
# Note: utils.sh and ssh.sh are sourced by the main script

# Function to sync a single item with retry
sync_item() {
    local source_user="$1"
    local source_host="$2"
    local source_path="$3"
    local dest_path="$4"
    local description="$5"
    local max_retries=3
    local retry_count=0

    print_info "Syncing: $description"
    print_info "From: $source_user@$source_host:$source_path"
    print_info "To: $dest_path"

    # Debug: Show what we're checking
    echo "DEBUG: Checking if path exists on remote..."
    echo "DEBUG: source_user='$source_user'"
    echo "DEBUG: source_host='$source_host'"
    echo "DEBUG: source_path='$source_path'"

    # Check if source is a file or directory
    local is_directory=0
    if ssh_cmd "$source_user@$source_host" "test -d \"$source_path\"" 2>/dev/null; then
        is_directory=1
        print_info "Detected as: directory"
    elif ssh_cmd "$source_user@$source_host" "test -f \"$source_path\"" 2>/dev/null; then
        is_directory=0
        print_info "Detected as: file"
    else
        print_error "Source path does not exist or is not accessible: $source_path"
        echo "DEBUG: Tried to access but failed. Running 'ls -la' on parent directory..."
        local parent_dir=$(dirname "$source_path")
        ssh_cmd "$source_user@$source_host" "ls -la \"$parent_dir\"" 2>&1 | head -20
        return 1
    fi

    # Prepare destination
    if [ $is_directory -eq 1 ]; then
        # For directories: ensure destination exists and NO trailing slash on source
        # rsync will copy the directory itself into dest
        [[ "$source_path" == */ ]] && source_path="${source_path%/}"
        [[ "$dest_path" != */ ]] && dest_path="${dest_path}/"
        mkdir -p "$dest_path"
    else
        # For files: ensure destination directory exists
        local dest_dir
        if [[ "$dest_path" == */ ]]; then
            dest_dir="$dest_path"
        else
            dest_dir="$(dirname "$dest_path")"
            dest_path="${dest_path}/"
        fi
        mkdir -p "$dest_dir"
    fi

    while [ $retry_count -lt $max_retries ]; do
        # Run rsync with password support and config options
        # Use RSYNC_OPTIONS from config, fallback to basic options if not set
        local rsync_opts="${RSYNC_OPTIONS:--avh --progress}"
        if rsync_cmd $rsync_opts "$source_user@$source_host:$source_path" "$dest_path"; then
            print_success "Successfully synced: $description"
            return 0
        else
            local rsync_exit_code=$?
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                print_warning "Sync failed for: $description (Exit code: $rsync_exit_code, Attempt $retry_count of $max_retries)"
                if ask_yes_no "Retry sync for $description?"; then
                    print_info "Retrying..."
                    continue
                else
                    print_error "Skipping: $description"
                    return 1
                fi
            else
                print_error "Failed to sync after $max_retries attempts: $description (Exit code: $rsync_exit_code)"
                return 1
            fi
        fi
    done

    return 1
}
