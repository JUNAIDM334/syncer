#!/bin/bash

# Files Discovery Module
# Discovers directories and hidden configuration files
# Note: utils.sh and ssh.sh are sourced by the main script

# Discover directories and hidden files on remote host
discover_files() {
    local source_user="$1"
    local source_host="$2"
    local source_home="$3"

    print_info "Discovering folders and files..."

    # Get list of directories in home folder
    print_info "Listing directories..."
    DISCOVERED_DIRS=$(ssh_cmd "$source_user@$source_host" "ls -d $source_home/*/ 2>/dev/null | xargs -n 1 basename" 2>/dev/null)
    if [ -n "$DISCOVERED_DIRS" ]; then
        echo "  Found $(echo "$DISCOVERED_DIRS" | wc -l) directories"
    fi

    # Get list of hidden config files/dirs
    print_info "Listing hidden files..."
    DISCOVERED_HIDDEN=$(ssh_cmd "$source_user@$source_host" "ls -ad $source_home/.* 2>/dev/null | grep -v -E '(^\.$|^\.\.$)' | xargs -n 1 basename" 2>/dev/null)
    if [ -n "$DISCOVERED_HIDDEN" ]; then
        echo "  Found $(echo "$DISCOVERED_HIDDEN" | wc -l) hidden files/dirs"
    fi

    # Export as global variables
    export DISCOVERED_DIRS
    export DISCOVERED_HIDDEN
}
