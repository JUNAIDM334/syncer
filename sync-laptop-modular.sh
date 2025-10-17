#!/bin/bash

# Modular Laptop Sync Script
# Syncs configuration files and data from a source Ubuntu laptop to the current laptop
#
# Usage:
#   ./sync-laptop-modular.sh                    # Interactive mode
#   ./sync-laptop-modular.sh --config FILE      # Use custom config file
#   ./sync-laptop-modular.sh --profile NAME     # Use predefined profile

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
CONFIG_FILE="$SCRIPT_DIR/config/defaults.conf"
if [ "$1" = "--config" ] && [ -n "$2" ]; then
    CONFIG_FILE="$2"
    shift 2
elif [ "$1" = "--profile" ] && [ -n "$2" ]; then
    CONFIG_FILE="$SCRIPT_DIR/config/sync-profiles/$2.conf"
    shift 2
fi

# Source configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Warning: Config file not found: $CONFIG_FILE"
    echo "Using defaults..."
fi

# Load library modules
source "$SCRIPT_DIR/lib/utils.sh" || { echo "Failed to load utils.sh"; exit 1; }
source "$SCRIPT_DIR/lib/ui-base.sh" || { echo "Failed to load ui-base.sh"; exit 1; }
source "$SCRIPT_DIR/lib/ssh.sh" || { echo "Failed to load ssh.sh"; exit 1; }

# Load discovery modules
source "$SCRIPT_DIR/modules/discovery/browsers.sh" || { echo "Failed to load browsers.sh"; exit 1; }
source "$SCRIPT_DIR/modules/discovery/databases.sh" || { echo "Failed to load databases.sh"; exit 1; }
source "$SCRIPT_DIR/modules/discovery/dev-tools.sh" || { echo "Failed to load dev-tools.sh"; exit 1; }
source "$SCRIPT_DIR/modules/discovery/files.sh" || { echo "Failed to load files.sh"; exit 1; }
source "$SCRIPT_DIR/modules/discovery/applications.sh" || { echo "Failed to load applications.sh"; exit 1; }

# Load sync modules
source "$SCRIPT_DIR/modules/sync/sync-core.sh" || { echo "Failed to load sync-core.sh"; exit 1; }
source "$SCRIPT_DIR/modules/sync/database-sync.sh" || { echo "Failed to load database-sync.sh"; exit 1; }

# Load installation module
source "$SCRIPT_DIR/modules/install/app-registry.sh" || { echo "Failed to load app-registry.sh"; exit 1; }
source "$SCRIPT_DIR/modules/install/installer.sh" || { echo "Failed to load installer.sh"; exit 1; }

# Debug: Check if functions are loaded
if ! declare -f discover_files > /dev/null; then
    echo "ERROR: discover_files function not found after sourcing modules!"
    echo "Checking what functions are available:"
    declare -F | grep discover
    exit 1
fi

# Load plugins if enabled
if [ "$ENABLE_PLUGINS" = "true" ]; then
    for plugin in "$SCRIPT_DIR/modules/plugins"/*.sh; do
        if [ -f "$plugin" ]; then
            print_info "Loading plugin: $(basename "$plugin")"
            source "$plugin"
        fi
    done
fi

# Global variables
SOURCE_USER=""
SOURCE_HOST=""
SOURCE_HOME=""
DEST_HOME="$HOME"

# Arrays to store discovered items
declare -A BROWSERS
declare -A DB_CLIENTS
declare -A DEV_TOOLS
declare -A OTHER_APPS
DISCOVERED_DIRS=""
DISCOVERED_HIDDEN=""

# Arrays for sync items
declare -a SYNC_ITEMS
declare -a APPS_TO_INSTALL
declare -a SELECTED_DATABASES

# Setup connection
setup_connection() {
    echo ""
    print_info "Please provide the source laptop details:"
    read -p "Source username: " SOURCE_USER
    read -p "Source IP address: " SOURCE_HOST
    read -p "Source home directory [/home/$SOURCE_USER]: " SOURCE_HOME
    SOURCE_HOME=${SOURCE_HOME:-/home/$SOURCE_USER}

    if ! test_ssh_connection "$SOURCE_USER" "$SOURCE_HOST"; then
        print_error "Failed to connect to source laptop"
        return 1
    fi

    return 0
}

# Run discovery
run_discovery() {
    print_info "Starting discovery process..."
    echo ""

    if [ "$DISCOVER_BROWSERS" = "true" ]; then
        discover_browsers "$SOURCE_USER" "$SOURCE_HOST" "$SOURCE_HOME"
        echo ""
    else
        print_info "Browser discovery disabled in profile"
    fi

    if [ "$DISCOVER_DATABASES" = "true" ]; then
        discover_databases "$SOURCE_USER" "$SOURCE_HOST" "$SOURCE_HOME"
        echo ""
    else
        print_info "Database discovery disabled in profile"
    fi

    if [ "$DISCOVER_DEV_TOOLS" = "true" ]; then
        discover_dev_tools "$SOURCE_USER" "$SOURCE_HOST" "$SOURCE_HOME"
        echo ""
    else
        print_info "Dev tools discovery disabled in profile"
    fi

    if [ "$DISCOVER_APPLICATIONS" != "false" ]; then
        discover_applications "$SOURCE_USER" "$SOURCE_HOST" "$SOURCE_HOME"
        echo ""
    else
        print_info "Applications discovery disabled in profile"
    fi

    if [ "$DISCOVER_FILES" = "true" ]; then
        discover_files "$SOURCE_USER" "$SOURCE_HOST" "$SOURCE_HOME"

        # Debug: Show what was discovered
        if [ -n "$DISCOVERED_DIRS" ]; then
            print_success "Discovered $(echo "$DISCOVERED_DIRS" | wc -l) directories"
        fi
        if [ -n "$DISCOVERED_HIDDEN" ]; then
            print_success "Discovered $(echo "$DISCOVERED_HIDDEN" | wc -l) hidden files/directories"
        fi
        echo ""
    else
        print_info "File discovery disabled in profile"
    fi

    print_success "Discovery complete!"
}

# Interactive selection for config files
select_config_files() {
    echo ""
    print_info "=== Configuration Files & Settings ==="
    echo ""

    # Check if any hidden files were discovered
    if [ -z "$DISCOVERED_HIDDEN" ]; then
        print_warning "No hidden configuration files discovered on source laptop"
        return
    fi

    print_info "Discovered hidden files/directories:"
    echo "$DISCOVERED_HIDDEN" | sed 's/^/  - /'
    echo ""
    print_info "Select what to sync:"
    echo ""

    # Important config files to ask about specifically
    declare -A IMPORTANT_CONFIGS=(
        [".ssh"]="SSH configuration"
        [".gitconfig"]="Git configuration"
        [".bash_aliases"]="Bash aliases"
        [".bashrc"]="Bashrc"
        [".aws"]="AWS configuration"
        [".config"]="Config directory"
        [".vscode"]="VSCode configuration"
    )

    # Ask about important configs first
    for config in "${!IMPORTANT_CONFIGS[@]}"; do
        if echo "$DISCOVERED_HIDDEN" | grep -q "^${config}$"; then
            if ask_yes_no "Sync ${IMPORTANT_CONFIGS[$config]} (~/$config)?"; then
                SYNC_ITEMS+=("$SOURCE_HOME/$config|$DEST_HOME/|${IMPORTANT_CONFIGS[$config]}")
            fi
        fi
    done

    # Ask about other hidden files
    OTHER_HIDDEN=""
    while IFS= read -r item; do
        [ -z "$item" ] && continue
        # Skip if already asked about
        if [[ ! " ${!IMPORTANT_CONFIGS[@]} " =~ " ${item} " ]]; then
            if [ -z "$OTHER_HIDDEN" ]; then
                OTHER_HIDDEN="$item"
            else
                OTHER_HIDDEN="${OTHER_HIDDEN}"$'\n'"${item}"
            fi
        fi
    done <<< "$DISCOVERED_HIDDEN"

    # Remove trailing newline and empty lines
    OTHER_HIDDEN=$(echo "$OTHER_HIDDEN" | grep -v "^$")

    if [ -n "$OTHER_HIDDEN" ]; then
        echo ""
        print_info "Other hidden files/directories found:"
        echo "$OTHER_HIDDEN" | sed 's/^/  - /'
        echo ""
        if ask_yes_no "Do you want to select from these other hidden files?"; then
            echo ""
            # Convert to array to avoid loop issues
            readarray -t other_hidden_array <<< "$OTHER_HIDDEN"
            for item in "${other_hidden_array[@]}"; do
                # Skip empty entries
                [[ -z "$item" ]] && continue
                if ask_yes_no "Sync ~/$item?"; then
                    SYNC_ITEMS+=("$SOURCE_HOME/$item|$DEST_HOME/|$item")
                fi
            done
        fi
    fi
}

# Interactive selection for browsers
select_browsers() {
    if [ ${#BROWSERS[@]} -eq 0 ]; then
        return
    fi

    echo ""
    print_info "=== Browser Data & Installation ==="
    echo ""

    for browser in "${!BROWSERS[@]}"; do
        IFS='|' read -r type path <<< "${BROWSERS[$browser]}"

        print_info "Found: $browser ($type)"

        # Check if installed locally
        if ! is_browser_installed "$browser"; then
            print_warning "$browser is not installed on this laptop"
            if ask_yes_no "Install $browser on this laptop?"; then
                APPS_TO_INSTALL+=("$browser|$type")
            fi
        fi

        # Ask about syncing data
        if ask_yes_no "Sync $browser profile data?"; then
            local dest_path
            case "$browser" in
                firefox)
                    [ "$type" = "snap" ] && dest_path="$DEST_HOME/snap/firefox/common/.mozilla/firefox/" || dest_path="$DEST_HOME/.mozilla/firefox/"
                    ;;
                google-chrome)
                    dest_path="$DEST_HOME/.config/google-chrome/"
                    ;;
                chromium)
                    [ "$type" = "snap" ] && dest_path="$DEST_HOME/snap/chromium/common/.config/chromium/" || dest_path="$DEST_HOME/.config/chromium/"
                    ;;
                brave)
                    dest_path="$DEST_HOME/.config/BraveSoftware/"
                    ;;
            esac
            SYNC_ITEMS+=("$path|$dest_path|$browser profile ($type)")
        fi
        echo ""
    done
}

# Interactive selection for applications
select_applications() {
    if [ ${#OTHER_APPS[@]} -eq 0 ]; then
        return
    fi

    echo ""
    print_info "=== Other Applications Installation ==="
    echo ""

    for app in "${!OTHER_APPS[@]}"; do
        IFS='|' read -r status type <<< "${OTHER_APPS[$app]}"

        if [ "$status" = "installed" ]; then
            print_info "Found: $app ($type)"

            # Check if installed locally
            if ! is_application_installed "$app"; then
                print_warning "$app is not installed on this laptop"
                if ask_yes_no "Install $app on this laptop?"; then
                    APPS_TO_INSTALL+=("$app|$type")
                fi
            else
                print_success "$app is already installed"
            fi
        fi
    done
}

# Interactive selection for directories
select_directories() {
    if [ -z "$DISCOVERED_DIRS" ]; then
        return
    fi

    echo ""
    print_info "=== User Directories ==="
    echo ""

    print_info "Discovered directories in home folder:"
    echo "$DISCOVERED_DIRS" | sed 's/^/  - /'
    echo ""

    # Common directories to ask about
    COMMON_DIRS=("Documents" "Downloads" "Desktop" "Pictures" "Videos" "Music" "workspace" "projects" "dev")

    print_info "Select directories to sync:"
    echo ""

    for dir in "${COMMON_DIRS[@]}"; do
        if echo "$DISCOVERED_DIRS" | grep -q "^${dir}$"; then
            if ask_yes_no "Sync $dir folder?"; then
                SYNC_ITEMS+=("$SOURCE_HOME/$dir|$DEST_HOME/|$dir")
            fi
        fi
    done

    # Ask about other directories
    OTHER_DIRS=$(echo "$DISCOVERED_DIRS" | grep -v -E "^(Documents|Downloads|Desktop|Pictures|Videos|Music|workspace|projects|dev|snap)$" | grep -v "^$")

    if [ -n "$OTHER_DIRS" ]; then
        echo ""
        print_info "Other directories found:"
        echo "$OTHER_DIRS" | sed 's/^/  - /'
        echo ""
        if ask_yes_no "Do you want to select from these other directories?"; then
            echo ""
            # Convert to array to avoid loop issues
            readarray -t other_dirs_array <<< "$OTHER_DIRS"
            for dir in "${other_dirs_array[@]}"; do
                # Skip empty entries
                [[ -z "$dir" ]] && continue
                if ask_yes_no "Sync '$dir' folder?"; then
                    SYNC_ITEMS+=("$SOURCE_HOME/$dir|$DEST_HOME/|$dir")
                fi
            done
        fi
    fi

    # Custom directory
    echo ""
    if ask_yes_no "Add custom directory path to sync?"; then
        while true; do
            read -p "Enter source path (relative to $SOURCE_HOME or absolute): " CUSTOM_SOURCE
            read -p "Enter destination path (relative to $DEST_HOME or absolute): " CUSTOM_DEST
            read -p "Enter description: " CUSTOM_DESC

            # Handle relative paths
            if [[ "$CUSTOM_SOURCE" != /* ]]; then
                CUSTOM_SOURCE="$SOURCE_HOME/$CUSTOM_SOURCE"
            fi
            if [[ "$CUSTOM_DEST" != /* ]]; then
                CUSTOM_DEST="$DEST_HOME/$CUSTOM_DEST"
            fi

            SYNC_ITEMS+=("$CUSTOM_SOURCE|$CUSTOM_DEST|$CUSTOM_DESC")

            if ! ask_yes_no "Add another custom directory?"; then
                break
            fi
        done
    fi
}

# Execute sync
execute_sync() {
    if [ ${#SYNC_ITEMS[@]} -eq 0 ]; then
        print_warning "No items selected for sync"
        return
    fi

    echo ""
    echo "=========================================="
    echo "  Starting Sync Process"
    echo "=========================================="
    echo ""

    local success_count=0
    local fail_count=0

    for item in "${SYNC_ITEMS[@]}"; do
        IFS='|' read -r source dest desc <<< "$item"
        if sync_item "$SOURCE_USER" "$SOURCE_HOST" "$source" "$dest" "$desc"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
        echo ""
    done

    # Fix SSH permissions if synced
    if [ -d "$DEST_HOME/.ssh" ]; then
        print_info "Fixing SSH directory permissions..."
        chmod 700 "$DEST_HOME/.ssh"
        chmod 600 "$DEST_HOME/.ssh/"* 2>/dev/null
        chmod 644 "$DEST_HOME/.ssh/"*.pub 2>/dev/null
        print_success "SSH permissions fixed"
    fi

    echo ""
    echo "=========================================="
    echo "  Sync Complete"
    echo "=========================================="
    print_success "Successfully synced: $success_count items"
    [ $fail_count -gt 0 ] && print_error "Failed to sync: $fail_count items"
    echo ""
}

# Execute installations
execute_installations() {
    if [ ${#APPS_TO_INSTALL[@]} -eq 0 ]; then
        return
    fi

    echo ""
    echo "=========================================="
    echo "  Installing Applications"
    echo "=========================================="
    echo ""

    for app_info in "${APPS_TO_INSTALL[@]}"; do
        IFS='|' read -r app type <<< "$app_info"
        install_application "$app" "$type"
        echo ""
    done
}

# Main function
main() {
    clear
    echo "=========================================="
    echo "  Modular Laptop Sync Script"
    echo "=========================================="
    echo ""

    # Check prerequisites
    check_rsync
    check_sshpass

    # Setup connection
    if ! setup_connection; then
        exit 1
    fi

    # Run discovery
    run_discovery

    # Interactive selection
    select_config_files
    select_browsers
    select_applications

    # Directory selection
    if [ -n "$DISCOVERED_DIRS" ]; then
        if [ "$SYNC_USER_DIRS" = "false" ]; then
            echo ""
            print_info "=== User Directories Discovered ==="
            echo "$DISCOVERED_DIRS" | sed 's/^/  - /'
            echo ""
            if ask_yes_no "Directory sync is disabled in profile. Enable it for this session?"; then
                select_directories
            fi
        else
            select_directories
        fi
    fi

    # Database selection (if enabled)
    if [ "$SYNC_DATABASES" = "true" ] && [ ${#DB_CLIENTS[@]} -gt 0 ]; then
        select_databases_to_sync "$SOURCE_USER" "$SOURCE_HOST" "$SOURCE_HOME"
    fi

    # Show summary
    echo ""
    echo "=========================================="
    echo "  Summary"
    echo "=========================================="
    echo "Items to sync: ${#SYNC_ITEMS[@]}"
    echo "Apps to install: ${#APPS_TO_INSTALL[@]}"
    if [ ${#SELECTED_DATABASES[@]} -gt 0 ]; then
        echo "Database data to sync: ${#SELECTED_DATABASES[@]}"
    fi
    echo ""

    if ! ask_yes_no "Proceed with sync and installation?"; then
        print_warning "Operation cancelled"
        exit 0
    fi

    # Execute installations first
    execute_installations

    # Execute regular file sync
    execute_sync

    # Execute database sync (data directories)
    if [ ${#SELECTED_DATABASES[@]} -gt 0 ]; then
        execute_database_sync "$SOURCE_USER" "$SOURCE_HOST" "$SOURCE_HOME"
    fi

    # Sync database config files (from SYNC_ITEMS)
    if [ ${#SYNC_ITEMS[@]} -gt 0 ]; then
        echo ""
        print_info "Syncing database configuration files..."
        echo ""
        for item in "${SYNC_ITEMS[@]}"; do
            if [[ "$item" == *"-pgpass"* ]] || [[ "$item" == *"-mycnf"* ]] || [[ "$item" == *"-mongorc"* ]] || [[ "$item" == "dbeaver-data" ]] || [[ "$item" == *"-system-config"* ]]; then
                sync_db_config_files "$SOURCE_USER" "$SOURCE_HOST" "$SOURCE_HOME" "$item"
                echo ""
            fi
        done
    fi

    print_success "All operations complete!"
    echo ""
}

# Run main function
main
