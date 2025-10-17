#!/bin/bash

# Laptop Sync Script - Menu-Based Version
# Syncs configuration files and data from a source Ubuntu laptop to the current laptop
#
# Usage:
#   ./sync-laptop.sh          # Normal mode with GUI dialogs
#   ./sync-laptop.sh --no-gui # Terminal-only mode (no dialogs)

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check for --no-gui flag
NO_GUI=0
if [ "$1" = "--no-gui" ] || [ "$1" = "-n" ] || [ "$1" = "--terminal" ]; then
    NO_GUI=1
    echo "Running in terminal-only mode (no GUI dialogs)"
fi

# Load library modules
source "$SCRIPT_DIR/lib/utils.sh" || { echo "Failed to load utils.sh"; exit 1; }
source "$SCRIPT_DIR/lib/ui-menu.sh" || { echo "Failed to load ui-menu.sh"; exit 1; }
source "$SCRIPT_DIR/lib/ssh.sh" || { echo "Failed to load ssh.sh"; exit 1; }

# Load discovery modules
source "$SCRIPT_DIR/modules/discovery/browsers.sh" || { echo "Failed to load browsers.sh"; exit 1; }
source "$SCRIPT_DIR/modules/discovery/databases.sh" || { echo "Failed to load databases.sh"; exit 1; }
source "$SCRIPT_DIR/modules/discovery/dev-tools.sh" || { echo "Failed to load dev-tools.sh"; exit 1; }
source "$SCRIPT_DIR/modules/discovery/files.sh" || { echo "Failed to load files.sh"; exit 1; }
source "$SCRIPT_DIR/modules/discovery/applications.sh" || { echo "Failed to load applications.sh"; exit 1; }

# Load sync modules
source "$SCRIPT_DIR/modules/sync/sync-core.sh" || { echo "Failed to load sync-core.sh"; exit 1; }

# Load installation module
source "$SCRIPT_DIR/modules/install/app-registry.sh" || { echo "Failed to load app-registry.sh"; exit 1; }
source "$SCRIPT_DIR/modules/install/installer.sh" || { echo "Failed to load installer.sh"; exit 1; }

# Global variables for connection
SOURCE_USER=""
SOURCE_HOST=""
SOURCE_HOME=""
DEST_HOME="$HOME"
USE_PASSWORD=0
SSH_PASSWORD=""

# Global arrays for discovered items
declare -A BROWSERS
declare -A DB_CLIENTS
declare -A DEV_TOOLS
declare -A OTHER_APPS
DISCOVERED_DIRS=""
DISCOVERED_HIDDEN=""

# Global arrays for selections
declare -a SELECTED_APPS_TO_INSTALL
declare -a SELECTED_SYNC_ITEMS
declare -a SELECTED_DB_BACKUPS

# Discovery completed flag
DISCOVERY_DONE=0

# Note: UI functions (show_msgbox, ask_yes_no, show_menu, show_checklist) are now in lib/ui-menu.sh
# Note: print_* functions are now in lib/utils.sh
# Note: SSH functions (ssh_cmd, rsync_cmd, test_ssh_connection, check_rsync, check_sshpass) are now in lib/ssh.sh

# Function to setup connection (menu-based version with whiptail support)
setup_connection() {
    if [ -n "$SOURCE_USER" ] && [ -n "$SOURCE_HOST" ]; then
        return 0
    fi

    SOURCE_USER=$(show_inputbox "Source Laptop" "Enter source username:" "")
    SOURCE_HOST=$(show_inputbox "Source Laptop" "Enter source IP address:" "")
    SOURCE_HOME=$(show_inputbox "Source Laptop" "Enter source home directory:" "/home/$SOURCE_USER")

    SOURCE_HOME=${SOURCE_HOME:-/home/$SOURCE_USER}

    if ! test_ssh_connection "$SOURCE_USER" "$SOURCE_HOST"; then
        show_msgbox "Error" "Failed to connect to source laptop.\nPlease check credentials and try again."
        return 1
    fi

    return 0
}

# Function to discover all items
discover_items() {
    if ! setup_connection; then
        return 1
    fi

    print_info "Discovering folders and installed applications on source laptop..."

    # Get list of directories in home folder
    print_info "Listing directories..."
    DISCOVERED_DIRS=$(ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "ls -d $SOURCE_HOME/*/ 2>/dev/null | xargs -n 1 basename" 2>/dev/null)
    if [ -n "$DISCOVERED_DIRS" ]; then
        echo "  Found $(echo "$DISCOVERED_DIRS" | wc -l) directories"
    fi

    # Get list of hidden config files/dirs
    print_info "Listing hidden files..."
    DISCOVERED_HIDDEN=$(ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "ls -ad $SOURCE_HOME/.* 2>/dev/null | grep -v -E '(^\.$|^\.\.$)' | xargs -n 1 basename" 2>/dev/null)
    if [ -n "$DISCOVERED_HIDDEN" ]; then
        echo "  Found $(echo "$DISCOVERED_HIDDEN" | wc -l) hidden files/dirs"
    fi

    print_info "Detecting browsers..."
    BROWSERS=()

    # Firefox - verify profile data exists
    if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "command -v firefox &>/dev/null" 2>/dev/null; then
        FIREFOX_TYPE=$(ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "snap list 2>/dev/null | grep -q firefox && echo 'snap' || echo 'native'" 2>/dev/null)
        if [ "$FIREFOX_TYPE" = "snap" ]; then
            if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "test -d $SOURCE_HOME/snap/firefox/common/.mozilla/firefox" 2>/dev/null; then
                BROWSERS["firefox"]="snap|$SOURCE_HOME/snap/firefox/common/.mozilla/firefox/"
                echo "  ✓ Firefox (snap)"
            else
                echo "  ⚠ Firefox (snap) installed but no profile data found"
            fi
        else
            if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "test -d $SOURCE_HOME/.mozilla/firefox" 2>/dev/null; then
                BROWSERS["firefox"]="native|$SOURCE_HOME/.mozilla/firefox/"
                echo "  ✓ Firefox (native)"
            else
                echo "  ⚠ Firefox (native) installed but no profile data found"
            fi
        fi
    fi

    # Chrome - verify profile data exists
    if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "command -v google-chrome &>/dev/null || command -v google-chrome-stable &>/dev/null" 2>/dev/null; then
        if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "test -d $SOURCE_HOME/.config/google-chrome" 2>/dev/null; then
            BROWSERS["google-chrome"]="native|$SOURCE_HOME/.config/google-chrome/"
            echo "  ✓ Google Chrome"
        else
            echo "  ⚠ Google Chrome installed but no profile data found"
        fi
    fi

    # Chromium - find actual profile path
    local chromium_type=""
    local chromium_path=""
    local chromium_found=0

    # Method 1: Check if snap chromium is installed
    if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "snap list chromium 2>/dev/null | grep -q '^chromium'" 2>/dev/null; then
        # Try multiple possible snap Chromium paths
        local snap_paths=(
            "$SOURCE_HOME/snap/chromium/common/.config/chromium"
            "$SOURCE_HOME/snap/chromium/current/.config/chromium"
            "$SOURCE_HOME/snap/chromium/.config/chromium"
        )

        for path in "${snap_paths[@]}"; do
            if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "test -d $path" 2>/dev/null; then
                chromium_type="snap"
                chromium_path="$path/"
                chromium_found=1
                echo "  ✓ Chromium (snap) - Path: $path"
                break
            fi
        done

        if [ $chromium_found -eq 0 ]; then
            # Try to find it dynamically
            local found_path=$(ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "find $SOURCE_HOME/snap/chromium -type d -name 'chromium' -path '*/.config/chromium' 2>/dev/null | head -1" 2>/dev/null)
            if [ -n "$found_path" ]; then
                chromium_type="snap"
                chromium_path="$found_path/"
                chromium_found=1
                echo "  ✓ Chromium (snap) - Found at: $found_path"
            else
                echo "  ⚠ Chromium (snap) installed but profile data not found"
                echo "    Searched paths:"
                for path in "${snap_paths[@]}"; do
                    echo "      - $path"
                done
            fi
        fi
    fi

    # Method 2: Check for native chromium if snap not found
    if [ $chromium_found -eq 0 ]; then
        if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "command -v chromium-browser &>/dev/null || command -v chromium &>/dev/null" 2>/dev/null; then
            # Verify the data directory exists
            if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "test -d $SOURCE_HOME/.config/chromium" 2>/dev/null; then
                chromium_type="native"
                chromium_path="$SOURCE_HOME/.config/chromium/"
                chromium_found=1
                echo "  ✓ Chromium (native)"
            else
                echo "  ⚠ Chromium (native) installed but no profile data found"
            fi
        fi
    fi

    # Method 3: Check if only config directory exists (was installed before)
    if [ $chromium_found -eq 0 ]; then
        if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "test -d $SOURCE_HOME/.config/chromium" 2>/dev/null; then
            chromium_type="native"
            chromium_path="$SOURCE_HOME/.config/chromium/"
            chromium_found=1
            echo "  ✓ Chromium (native - profile data only)"
        fi
    fi

    # Only add to BROWSERS if we found valid profile data
    if [ $chromium_found -eq 1 ]; then
        BROWSERS["chromium"]="$chromium_type|$chromium_path"
    fi

    # Brave
    if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "command -v brave-browser &>/dev/null" 2>/dev/null; then
        if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "test -d $SOURCE_HOME/.config/BraveSoftware" 2>/dev/null; then
            BROWSERS["brave"]="native|$SOURCE_HOME/.config/BraveSoftware/"
            echo "  ✓ Brave Browser"
        fi
    fi

    print_info "Detecting database clients..."
    DB_CLIENTS=()

    # PostgreSQL
    if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "command -v psql &>/dev/null" 2>/dev/null; then
        PSQL_VERSION=$(ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "psql --version 2>/dev/null | awk '{print \$3}'" 2>/dev/null)
        DB_CLIENTS["postgresql"]="installed|$PSQL_VERSION"
        echo "  ✓ PostgreSQL ($PSQL_VERSION)"
        if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "test -f $SOURCE_HOME/.pgpass" 2>/dev/null; then
            DB_CLIENTS["postgresql-pgpass"]="config|$SOURCE_HOME/.pgpass"
        fi
        if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "test -f $SOURCE_HOME/.psqlrc" 2>/dev/null; then
            DB_CLIENTS["postgresql-psqlrc"]="config|$SOURCE_HOME/.psqlrc"
        fi
    fi

    # MySQL/MariaDB
    if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "command -v mysql &>/dev/null" 2>/dev/null; then
        MYSQL_VERSION=$(ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "mysql --version 2>/dev/null | awk '{print \$5}' | cut -d, -f1" 2>/dev/null)
        DB_CLIENTS["mysql"]="installed|$MYSQL_VERSION"
        echo "  ✓ MySQL/MariaDB ($MYSQL_VERSION)"
        if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "test -f $SOURCE_HOME/.my.cnf" 2>/dev/null; then
            DB_CLIENTS["mysql-config"]="config|$SOURCE_HOME/.my.cnf"
        fi
    fi

    # MongoDB
    if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "command -v mongosh &>/dev/null || command -v mongo &>/dev/null" 2>/dev/null; then
        MONGO_VERSION=$(ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "mongosh --version 2>/dev/null || mongo --version 2>/dev/null | head -1 | awk '{print \$4}'" 2>/dev/null)
        DB_CLIENTS["mongodb"]="installed|$MONGO_VERSION"
        echo "  ✓ MongoDB ($MONGO_VERSION)"
        if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "test -f $SOURCE_HOME/.mongorc.js" 2>/dev/null; then
            DB_CLIENTS["mongodb-config"]="config|$SOURCE_HOME/.mongorc.js"
        fi
    fi

    # Redis
    if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "command -v redis-cli &>/dev/null" 2>/dev/null; then
        REDIS_VERSION=$(ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "redis-cli --version 2>/dev/null | awk '{print \$2}'" 2>/dev/null)
        DB_CLIENTS["redis"]="installed|$REDIS_VERSION"
        echo "  ✓ Redis ($REDIS_VERSION)"
    fi

    # DBeaver
    if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "command -v dbeaver &>/dev/null || test -d $SOURCE_HOME/.local/share/DBeaverData" 2>/dev/null; then
        DB_CLIENTS["dbeaver"]="installed|gui"
        if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "test -d $SOURCE_HOME/.local/share/DBeaverData" 2>/dev/null; then
            DB_CLIENTS["dbeaver-data"]="config|$SOURCE_HOME/.local/share/DBeaverData/"
        fi
    fi

    print_info "Detecting development tools..."
    DEV_TOOLS=()

    # VSCode
    if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "command -v code &>/dev/null" 2>/dev/null; then
        DEV_TOOLS["vscode"]="installed|IDE"
        echo "  ✓ VSCode"
        if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "test -d $SOURCE_HOME/.config/Code" 2>/dev/null; then
            DEV_TOOLS["vscode-config"]="config|$SOURCE_HOME/.config/Code/"
        fi
    fi

    # Docker
    if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "command -v docker &>/dev/null" 2>/dev/null; then
        DOCKER_VERSION=$(ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "docker --version 2>/dev/null | awk '{print \$3}' | cut -d, -f1" 2>/dev/null)
        DEV_TOOLS["docker"]="installed|$DOCKER_VERSION"
        echo "  ✓ Docker ($DOCKER_VERSION)"
        if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "test -d $SOURCE_HOME/.docker" 2>/dev/null; then
            DEV_TOOLS["docker-config"]="config|$SOURCE_HOME/.docker/"
        fi
    fi

    # Node.js
    if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "command -v node &>/dev/null" 2>/dev/null; then
        NODE_VERSION=$(ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "node --version 2>/dev/null" 2>/dev/null)
        DEV_TOOLS["nodejs"]="installed|$NODE_VERSION"
        echo "  ✓ Node.js ($NODE_VERSION)"
        if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "test -f $SOURCE_HOME/.npmrc" 2>/dev/null; then
            DEV_TOOLS["npm-config"]="config|$SOURCE_HOME/.npmrc"
        fi
    fi

    # Python
    if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "command -v python3 &>/dev/null" 2>/dev/null; then
        PYTHON_VERSION=$(ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "python3 --version 2>/dev/null | awk '{print \$2}'" 2>/dev/null)
        DEV_TOOLS["python3"]="installed|$PYTHON_VERSION"
        echo "  ✓ Python ($PYTHON_VERSION)"
    fi

    # Git
    if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "command -v git &>/dev/null" 2>/dev/null; then
        GIT_VERSION=$(ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "git --version 2>/dev/null | awk '{print \$3}'" 2>/dev/null)
        DEV_TOOLS["git"]="installed|$GIT_VERSION"
        echo "  ✓ Git ($GIT_VERSION)"
    fi

    print_info "Detecting other applications..."
    OTHER_APPS=()

    # Common applications to check
    # Media players
    if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "command -v vlc &>/dev/null" 2>/dev/null; then
        OTHER_APPS["vlc"]="installed|media-player"
        echo "  ✓ VLC Media Player"
    fi

    if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "snap list 2>/dev/null | grep -q '^stremio '" 2>/dev/null; then
        OTHER_APPS["stremio"]="installed|snap"
        echo "  ✓ Stremio (snap)"
    elif ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "command -v stremio &>/dev/null" 2>/dev/null; then
        OTHER_APPS["stremio"]="installed|native"
        echo "  ✓ Stremio (native)"
    fi

    # Communication
    if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "snap list 2>/dev/null | grep -q '^slack '" 2>/dev/null; then
        OTHER_APPS["slack"]="installed|snap"
        echo "  ✓ Slack (snap)"
    elif ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "command -v slack &>/dev/null" 2>/dev/null; then
        OTHER_APPS["slack"]="installed|native"
        echo "  ✓ Slack (native)"
    fi

    if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "snap list 2>/dev/null | grep -q '^discord '" 2>/dev/null; then
        OTHER_APPS["discord"]="installed|snap"
        echo "  ✓ Discord (snap)"
    elif ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "command -v discord &>/dev/null" 2>/dev/null; then
        OTHER_APPS["discord"]="installed|native"
        echo "  ✓ Discord (native)"
    fi

    if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "snap list 2>/dev/null | grep -q '^skype '" 2>/dev/null; then
        OTHER_APPS["skype"]="installed|snap"
        echo "  ✓ Skype (snap)"
    elif ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "command -v skypeforlinux &>/dev/null" 2>/dev/null; then
        OTHER_APPS["skype"]="installed|native"
        echo "  ✓ Skype (native)"
    fi

    # Utilities
    if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "command -v gimp &>/dev/null" 2>/dev/null; then
        OTHER_APPS["gimp"]="installed|graphics"
        echo "  ✓ GIMP"
    fi

    if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "command -v inkscape &>/dev/null" 2>/dev/null; then
        OTHER_APPS["inkscape"]="installed|graphics"
        echo "  ✓ Inkscape"
    fi

    if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "snap list 2>/dev/null | grep -q '^postman '" 2>/dev/null; then
        OTHER_APPS["postman"]="installed|snap"
        echo "  ✓ Postman (snap)"
    fi

    if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "snap list 2>/dev/null | grep -q '^insomnia '" 2>/dev/null; then
        OTHER_APPS["insomnia"]="installed|snap"
        echo "  ✓ Insomnia (snap)"
    fi

    # Office
    if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "command -v libreoffice &>/dev/null" 2>/dev/null; then
        OTHER_APPS["libreoffice"]="installed|office"
        echo "  ✓ LibreOffice"
    fi

    # Torrent clients
    if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "command -v qbittorrent &>/dev/null" 2>/dev/null; then
        OTHER_APPS["qbittorrent"]="installed|torrent"
        echo "  ✓ qBittorrent"
    fi

    if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "command -v transmission-gtk &>/dev/null" 2>/dev/null; then
        OTHER_APPS["transmission"]="installed|torrent"
        echo "  ✓ Transmission"
    fi

    DISCOVERY_DONE=1
    print_success "Discovery complete!"

    # Build summary message for scrollable view
    local summary="DISCOVERY COMPLETE\n\n"

    summary+="=== BROWSERS ===\n"
    if [ ${#BROWSERS[@]} -gt 0 ]; then
        for browser in "${!BROWSERS[@]}"; do
            IFS='|' read -r type path <<< "${BROWSERS[$browser]}"
            summary+="- $browser ($type)\n"
        done
    else
        summary+="No browsers detected\n"
    fi

    summary+="\n=== DATABASE CLIENTS ===\n"
    if [ ${#DB_CLIENTS[@]} -gt 0 ]; then
        for db in "${!DB_CLIENTS[@]}"; do
            IFS='|' read -r type info <<< "${DB_CLIENTS[$db]}"
            if [ "$type" = "installed" ]; then
                summary+="- $db (v$info)\n"
            fi
        done
    else
        summary+="No database clients detected\n"
    fi

    summary+="\n=== DEVELOPMENT TOOLS ===\n"
    if [ ${#DEV_TOOLS[@]} -gt 0 ]; then
        for tool in "${!DEV_TOOLS[@]}"; do
            IFS='|' read -r type info <<< "${DEV_TOOLS[$tool]}"
            if [ "$type" = "installed" ]; then
                summary+="- $tool ($info)\n"
            fi
        done
    else
        summary+="No development tools detected\n"
    fi

    summary+="\n=== OTHER APPLICATIONS ===\n"
    if [ ${#OTHER_APPS[@]} -gt 0 ]; then
        for app in "${!OTHER_APPS[@]}"; do
            IFS='|' read -r type info <<< "${OTHER_APPS[$app]}"
            if [ "$type" = "installed" ]; then
                summary+="- $app ($info)\n"
            fi
        done
    else
        summary+="No other applications detected\n"
    fi

    summary+="\n=== DIRECTORIES ===\n"
    if [ -n "$DISCOVERED_DIRS" ]; then
        summary+="$(echo "$DISCOVERED_DIRS" | head -10 | sed 's/^/- /')\n"
        local dir_count=$(echo "$DISCOVERED_DIRS" | wc -l)
        if [ $dir_count -gt 10 ]; then
            summary+="... and $((dir_count - 10)) more\n"
        fi
    else
        summary+="No directories found\n"
    fi

    # Print to terminal only
    echo ""
    echo "=========================================="
    echo "         DISCOVERY RESULTS"
    echo "=========================================="
    echo -e "$summary"
    echo "=========================================="
    echo ""
    echo "Press Enter to continue..."
    read
}

# Function to view discovery list
view_discovery_list() {
    if [ $DISCOVERY_DONE -eq 0 ]; then
        echo ""
        echo -e "${YELLOW}[WARNING]${NC} Discovery not done yet. Please run option 1 first."
        echo ""
        echo "Press Enter to continue..."
        read
        return
    fi

    # Build summary
    local summary=""

    summary+="=== BROWSERS ===\n"
    if [ ${#BROWSERS[@]} -gt 0 ]; then
        for browser in "${!BROWSERS[@]}"; do
            IFS='|' read -r type path <<< "${BROWSERS[$browser]}"
            summary+="- $browser ($type): $path\n"
        done
    else
        summary+="No browsers detected\n"
    fi

    summary+="\n=== DATABASE CLIENTS ===\n"
    if [ ${#DB_CLIENTS[@]} -gt 0 ]; then
        for db in "${!DB_CLIENTS[@]}"; do
            IFS='|' read -r type info <<< "${DB_CLIENTS[$db]}"
            if [ "$type" = "installed" ]; then
                summary+="- $db ($info)\n"
            fi
        done
    else
        summary+="No database clients detected\n"
    fi

    summary+="\n=== DEVELOPMENT TOOLS ===\n"
    if [ ${#DEV_TOOLS[@]} -gt 0 ]; then
        for tool in "${!DEV_TOOLS[@]}"; do
            IFS='|' read -r type info <<< "${DEV_TOOLS[$tool]}"
            if [ "$type" = "installed" ]; then
                summary+="- $tool ($info)\n"
            fi
        done
    else
        summary+="No development tools detected\n"
    fi

    summary+="\n=== OTHER APPLICATIONS ===\n"
    if [ ${#OTHER_APPS[@]} -gt 0 ]; then
        for app in "${!OTHER_APPS[@]}"; do
            IFS='|' read -r type info <<< "${OTHER_APPS[$app]}"
            if [ "$type" = "installed" ]; then
                summary+="- $app ($info)\n"
            fi
        done
    else
        summary+="No other applications detected\n"
    fi

    summary+="\n=== DIRECTORIES ===\n"
    if [ -n "$DISCOVERED_DIRS" ]; then
        summary+="$(echo "$DISCOVERED_DIRS" | sed 's/^/- /')\n"
        local dir_count=$(echo "$DISCOVERED_DIRS" | wc -l)
        summary+="\nTotal: $dir_count directories\n"
    else
        summary+="No directories found\n"
    fi

    summary+="\n=== HIDDEN FILES/DIRS ===\n"
    if [ -n "$DISCOVERED_HIDDEN" ]; then
        summary+="$(echo "$DISCOVERED_HIDDEN" | head -20 | sed 's/^/- /')\n"
        local hidden_count=$(echo "$DISCOVERED_HIDDEN" | wc -l)
        if [ $hidden_count -gt 20 ]; then
            summary+="... and $((hidden_count - 20)) more\n"
        fi
        summary+="\nTotal: $hidden_count hidden items\n"
    else
        summary+="No hidden files found\n"
    fi

    # Print to terminal
    echo ""
    echo "=========================================="
    echo "         DISCOVERY RESULTS"
    echo "=========================================="
    echo -e "$summary"
    echo "=========================================="
    echo ""
    echo "Press Enter to continue..."
    read
}

# Main menu
main_menu() {
    while true; do
        local discovery_status="Not done"
        [ $DISCOVERY_DONE -eq 1 ] && discovery_status="Complete"

        local selections_count=$((${#SELECTED_APPS_TO_INSTALL[@]} + ${#SELECTED_SYNC_ITEMS[@]} + ${#SELECTED_DB_BACKUPS[@]}))

        CHOICE=$(show_menu "Ubuntu Laptop Sync - Main Menu" \
            "1" "Discover & Show Available Items [$discovery_status]" \
            "2" "View Discovery List" \
            "3" "Install Applications" \
            "4" "Sync Configuration Files" \
            "5" "Sync Browser Data" \
            "6" "Backup & Restore Databases" \
            "7" "Sync Development Tools Config" \
            "8" "Sync User Directories" \
            "9" "Sync Custom Directory" \
            "10" "Execute All Operations [$selections_count queued]" \
            "11" "View Current Selections" \
            "12" "Clear All Selections" \
            "13" "Exit")

        case $CHOICE in
            1) discover_items ;;
            2) view_discovery_list ;;
            3) menu_install_applications ;;
            4) menu_sync_config_files ;;
            5) menu_sync_browsers ;;
            6) menu_backup_databases ;;
            7) menu_sync_dev_tools ;;
            8) menu_sync_user_dirs ;;
            9) menu_sync_custom_dir ;;
            10) execute_all_operations ;;
            11) view_selections ;;
            12) clear_selections ;;
            13|"") exit 0 ;;
        esac
    done
}

# Function to check if app is installed locally
is_app_installed() {
    local app="$1"
    case "$app" in
        firefox) command -v firefox &>/dev/null ;;
        google-chrome) command -v google-chrome &>/dev/null || command -v google-chrome-stable &>/dev/null ;;
        chromium) command -v chromium &>/dev/null || command -v chromium-browser &>/dev/null ;;
        brave) command -v brave-browser &>/dev/null ;;
        postgresql) command -v psql &>/dev/null ;;
        mysql) command -v mysql &>/dev/null ;;
        mongodb) command -v mongosh &>/dev/null || command -v mongo &>/dev/null ;;
        redis) command -v redis-cli &>/dev/null ;;
        dbeaver) command -v dbeaver &>/dev/null ;;
        vscode) command -v code &>/dev/null ;;
        docker) command -v docker &>/dev/null ;;
        nodejs) command -v node &>/dev/null ;;
        python3) command -v python3 &>/dev/null ;;
        git) command -v git &>/dev/null ;;
        vlc) command -v vlc &>/dev/null ;;
        stremio) command -v stremio &>/dev/null || snap list 2>/dev/null | grep -q '^stremio ' ;;
        slack) command -v slack &>/dev/null || snap list 2>/dev/null | grep -q '^slack ' ;;
        discord) command -v discord &>/dev/null || snap list 2>/dev/null | grep -q '^discord ' ;;
        skype) command -v skypeforlinux &>/dev/null || snap list 2>/dev/null | grep -q '^skype ' ;;
        gimp) command -v gimp &>/dev/null ;;
        inkscape) command -v inkscape &>/dev/null ;;
        postman) snap list 2>/dev/null | grep -q '^postman ' ;;
        insomnia) snap list 2>/dev/null | grep -q '^insomnia ' ;;
        libreoffice) command -v libreoffice &>/dev/null ;;
        qbittorrent) command -v qbittorrent &>/dev/null ;;
        transmission) command -v transmission-gtk &>/dev/null ;;
        *) return 1 ;;
    esac
}

# Function to install application with robust error handling
install_application() {
    local app="$1"
    local type="$2"
    local install_status=0

    print_info "Installing: $app ($type)"

    case "$app" in
        firefox)
            if [ "$type" = "snap" ]; then
                sudo snap install firefox || install_status=$?
            else
                sudo apt update || true
                sudo apt install -y firefox || install_status=$?
            fi
            ;;
        google-chrome)
            if ! wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo apt-key add -; then
                print_warning "Failed to add Chrome signing key, trying alternative method..."
                wget -q -O /tmp/chrome.pub https://dl.google.com/linux/linux_signing_key.pub
                sudo apt-key add /tmp/chrome.pub
                rm /tmp/chrome.pub
            fi
            echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list
            sudo apt update || true
            sudo apt install -y google-chrome-stable || install_status=$?
            ;;
        chromium)
            if [ "$type" = "snap" ]; then
                sudo snap install chromium || install_status=$?
            else
                sudo apt update || true
                sudo apt install -y chromium-browser || install_status=$?
            fi
            ;;
        brave)
            sudo apt install -y curl || true
            if curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg; then
                echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" | sudo tee /etc/apt/sources.list.d/brave-browser-release.list
                sudo apt update || true
                sudo apt install -y brave-browser || install_status=$?
            else
                print_error "Failed to download Brave repository key"
                install_status=1
            fi
            ;;
        postgresql)
            sudo apt update || true
            sudo apt install -y postgresql-client postgresql-client-common || install_status=$?
            ;;
        mysql)
            sudo apt update || true
            sudo apt install -y mysql-client || install_status=$?
            ;;
        mongodb)
            sudo apt update || true
            # Try mongodb-clients or mongosh
            sudo apt install -y mongodb-clients || sudo apt install -y mongosh || install_status=$?
            ;;
        redis)
            sudo apt update || true
            sudo apt install -y redis-tools || install_status=$?
            ;;
        dbeaver)
            if wget -O /tmp/dbeaver.deb https://dbeaver.io/files/dbeaver-ce_latest_amd64.deb; then
                sudo dpkg -i /tmp/dbeaver.deb || true
                sudo apt-get install -f -y || install_status=$?
                rm -f /tmp/dbeaver.deb
            else
                print_error "Failed to download DBeaver"
                install_status=1
            fi
            ;;
        vscode)
            if wget -q -O - https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -; then
                echo "deb [arch=amd64] https://packages.microsoft.com/repos/vscode stable main" | sudo tee /etc/apt/sources.list.d/vscode.list
                sudo apt update || true
                sudo apt install -y code || install_status=$?
            else
                print_error "Failed to add VSCode repository"
                install_status=1
            fi
            ;;
        docker)
            sudo apt update || true
            sudo apt install -y ca-certificates curl gnupg || true
            sudo install -m 0755 -d /etc/apt/keyrings
            if curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null; then
                sudo chmod a+r /etc/apt/keyrings/docker.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
                sudo apt update || true
                sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || install_status=$?
                sudo usermod -aG docker $USER || true
            else
                print_error "Failed to download Docker GPG key"
                install_status=1
            fi
            ;;
        nodejs)
            if curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -; then
                sudo apt install -y nodejs || install_status=$?
            else
                print_warning "NodeSource setup failed, trying default nodejs..."
                sudo apt update || true
                sudo apt install -y nodejs npm || install_status=$?
            fi
            ;;
        python3)
            sudo apt update || true
            sudo apt install -y python3 python3-pip || install_status=$?
            ;;
        git)
            sudo apt update || true
            sudo apt install -y git || install_status=$?
            ;;
        vlc)
            sudo apt update || true
            sudo apt install -y vlc || install_status=$?
            ;;
        stremio)
            if [ "$type" = "snap" ]; then
                sudo snap install stremio || install_status=$?
            else
                print_warning "Stremio native installation requires manual download from https://www.stremio.com/downloads"
                install_status=1
            fi
            ;;
        slack)
            if [ "$type" = "snap" ]; then
                sudo snap install slack --classic || install_status=$?
            else
                if wget https://downloads.slack-edge.com/releases/linux/4.36.140/prod/x64/slack-desktop-4.36.140-amd64.deb -O /tmp/slack.deb 2>/dev/null; then
                    sudo dpkg -i /tmp/slack.deb || true
                    sudo apt-get install -f -y || install_status=$?
                    rm -f /tmp/slack.deb
                else
                    print_error "Failed to download Slack"
                    install_status=1
                fi
            fi
            ;;
        discord)
            if [ "$type" = "snap" ]; then
                sudo snap install discord || install_status=$?
            else
                if wget "https://discord.com/api/download?platform=linux&format=deb" -O /tmp/discord.deb 2>/dev/null; then
                    sudo dpkg -i /tmp/discord.deb || true
                    sudo apt-get install -f -y || install_status=$?
                    rm -f /tmp/discord.deb
                else
                    print_error "Failed to download Discord"
                    install_status=1
                fi
            fi
            ;;
        skype)
            if [ "$type" = "snap" ]; then
                sudo snap install skype --classic || install_status=$?
            else
                if wget https://go.skype.com/skypeforlinux-64.deb -O /tmp/skype.deb 2>/dev/null; then
                    sudo dpkg -i /tmp/skype.deb || true
                    sudo apt-get install -f -y || install_status=$?
                    rm -f /tmp/skype.deb
                else
                    print_error "Failed to download Skype"
                    install_status=1
                fi
            fi
            ;;
        gimp)
            sudo apt update || true
            sudo apt install -y gimp || install_status=$?
            ;;
        inkscape)
            sudo apt update || true
            sudo apt install -y inkscape || install_status=$?
            ;;
        postman)
            sudo snap install postman || install_status=$?
            ;;
        insomnia)
            sudo snap install insomnia || install_status=$?
            ;;
        libreoffice)
            sudo apt update || true
            sudo apt install -y libreoffice || install_status=$?
            ;;
        qbittorrent)
            sudo apt update || true
            sudo apt install -y qbittorrent || install_status=$?
            ;;
        transmission)
            sudo apt update || true
            sudo apt install -y transmission-gtk || install_status=$?
            ;;
        *)
            print_error "Unknown application: $app"
            return 1
            ;;
    esac

    # Verify installation
    if [ $install_status -eq 0 ]; then
        if is_app_installed "$app"; then
            print_success "Successfully installed and verified: $app"
            return 0
        else
            print_warning "Installation completed but verification failed for: $app"
            print_info "The app may need a system restart or manual verification"
            return 0
        fi
    else
        print_error "Failed to install: $app (exit code: $install_status)"
        return 1
    fi
}

# Menu option: Install Applications
menu_install_applications() {
    if [ $DISCOVERY_DONE -eq 0 ]; then
        show_msgbox "Error" "Please run 'Discover & Show Available Items' first!"
        return
    fi

    # Build list of apps not installed locally
    declare -a available_apps
    declare -a checklist_options

    # Check browsers
    for browser in "${!BROWSERS[@]}"; do
        IFS='|' read -r type path <<< "${BROWSERS[$browser]}"
        if ! is_app_installed "$browser"; then
            available_apps+=("$browser|$type|browser")
            checklist_options+=("$browser" "$browser ($type) - Browser" "OFF")
        fi
    done

    # Check database clients
    for db in "${!DB_CLIENTS[@]}"; do
        IFS='|' read -r dbtype info <<< "${DB_CLIENTS[$db]}"
        if [ "$dbtype" = "installed" ]; then
            if ! is_app_installed "$db"; then
                available_apps+=("$db|$info|database")
                checklist_options+=("$db" "$db (v$info) - Database Client" "OFF")
            fi
        fi
    done

    # Check dev tools
    for tool in "${!DEV_TOOLS[@]}"; do
        IFS='|' read -r tooltype info <<< "${DEV_TOOLS[$tool]}"
        if [ "$tooltype" = "installed" ]; then
            if ! is_app_installed "$tool"; then
                available_apps+=("$tool|$info|devtool")
                checklist_options+=("$tool" "$tool ($info) - Development Tool" "OFF")
            fi
        fi
    done

    # Check other applications
    for app in "${!OTHER_APPS[@]}"; do
        IFS='|' read -r apptype info <<< "${OTHER_APPS[$app]}"
        if [ "$apptype" = "installed" ]; then
            if ! is_app_installed "$app"; then
                available_apps+=("$app|$info|application")
                checklist_options+=("$app" "$app ($info) - Application" "OFF")
            fi
        fi
    done

    # Check if any apps are available to install
    if [ ${#available_apps[@]} -eq 0 ]; then
        show_msgbox "Info" "All applications from source laptop are already installed on this system!"
        return
    fi

    # Show checklist
    local selected=$(show_checklist "Install Applications" "Select applications to install:" "${checklist_options[@]}")

    # Check if user cancelled or selected nothing
    if [ -z "$selected" ]; then
        return
    fi

    # Parse selected items (remove quotes and split)
    selected=$(echo "$selected" | tr -d '"')

    # Show dry run summary
    local summary="The following applications will be INSTALLED:\n\n"
    for app in $selected; do
        for available in "${available_apps[@]}"; do
            IFS='|' read -r app_name app_type app_category <<< "$available"
            if [ "$app_name" = "$app" ]; then
                summary+="- $app_name ($app_type)\n"
                break
            fi
        done
    done

    summary+="\nThis will require sudo privileges and internet connection.\n\nProceed with installation?"

    if ! ask_yes_no "$summary"; then
        return
    fi

    # Install selected applications
    echo ""
    echo "=========================================="
    echo "  Installing Applications"
    echo "=========================================="
    echo ""

    local success_count=0
    local fail_count=0

    for app in $selected; do
        # Find app type
        local app_type=""
        for available in "${available_apps[@]}"; do
            IFS='|' read -r app_name type category <<< "$available"
            if [ "$app_name" = "$app" ]; then
                app_type="$type"
                break
            fi
        done

        if install_application "$app" "$app_type"; then
            SELECTED_APPS_TO_INSTALL+=("$app")
            ((success_count++))
        else
            ((fail_count++))
        fi
        echo ""
    done

    # Show results
    local result="Installation Complete!\n\n"
    result+="Successfully installed: $success_count\n"
    [ $fail_count -gt 0 ] && result+="Failed: $fail_count\n"

    show_msgbox "Installation Results" "$result"
}

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

    # Create destination directory if it doesn't exist
    mkdir -p "$dest_path"

    while [ $retry_count -lt $max_retries ]; do
        # Run rsync with password support
        if rsync_cmd -avh --progress "$source_user@$source_host:$source_path" "$dest_path"; then
            print_success "Successfully synced: $description"
            return 0
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                print_warning "Sync failed for: $description (Attempt $retry_count of $max_retries)"
                if ask_yes_no "Retry sync for $description?"; then
                    print_info "Retrying..."
                    continue
                else
                    print_error "Skipping: $description"
                    return 1
                fi
            else
                print_error "Failed to sync after $max_retries attempts: $description"
                return 1
            fi
        fi
    done

    return 1
}

# Menu option: Sync Configuration Files
menu_sync_config_files() {
    if [ $DISCOVERY_DONE -eq 0 ]; then
        show_msgbox "Error" "Please run 'Discover & Show Available Items' first!"
        return
    fi

    # Build list of available config files
    declare -a available_configs
    declare -a checklist_options

    # SSH Configuration
    if echo "$DISCOVERED_HIDDEN" | grep -q "^\.ssh$"; then
        available_configs+=(".ssh|$SOURCE_HOME/.ssh|$DEST_HOME/|SSH Keys and Config")
        checklist_options+=(".ssh" "SSH Keys and Configuration" "OFF")
    fi

    # Git Configuration
    if echo "$DISCOVERED_HIDDEN" | grep -q "^\.gitconfig$"; then
        available_configs+=(".gitconfig|$SOURCE_HOME/.gitconfig|$DEST_HOME/|Git Configuration")
        checklist_options+=(".gitconfig" "Git Configuration" "OFF")
    fi

    # Bash Aliases
    if echo "$DISCOVERED_HIDDEN" | grep -q "^\.bash_aliases$"; then
        available_configs+=(".bash_aliases|$SOURCE_HOME/.bash_aliases|$DEST_HOME/|Bash Aliases")
        checklist_options+=(".bash_aliases" "Bash Aliases" "OFF")
    fi

    # Bashrc
    if echo "$DISCOVERED_HIDDEN" | grep -q "^\.bashrc$"; then
        available_configs+=(".bashrc|$SOURCE_HOME/.bashrc|$DEST_HOME/|Bash Configuration")
        checklist_options+=(".bashrc" "Bash Configuration (.bashrc)" "OFF")
    fi

    # AWS Configuration
    if echo "$DISCOVERED_HIDDEN" | grep -q "^\.aws$"; then
        available_configs+=(".aws|$SOURCE_HOME/.aws|$DEST_HOME/|AWS Configuration")
        checklist_options+=(".aws" "AWS Configuration" "OFF")
    fi

    # Docker Configuration
    if echo "$DISCOVERED_HIDDEN" | grep -q "^\.docker$"; then
        available_configs+=(".docker|$SOURCE_HOME/.docker|$DEST_HOME/|Docker Configuration")
        checklist_options+=(".docker" "Docker Configuration" "OFF")
    fi

    # Check if any configs are available
    if [ ${#available_configs[@]} -eq 0 ]; then
        show_msgbox "Info" "No configuration files found on source laptop!"
        return
    fi

    # Show checklist
    local selected=$(show_checklist "Sync Configuration Files" "Select configuration files to sync:" "${checklist_options[@]}")

    # Check if user cancelled or selected nothing
    if [ -z "$selected" ]; then
        return
    fi

    # Parse selected items
    selected=$(echo "$selected" | tr -d '"')

    # Ask if user wants to backup existing configs or customize destination
    echo ""
    echo "Options for syncing configuration files:"
    echo "1. Replace existing configs (default behavior)"
    echo "2. Backup existing configs before replacing"
    echo "3. Sync to custom location"
    echo ""
    echo -n "Enter choice (1/2/3) [1]: "
    read sync_option
    sync_option=${sync_option:-1}

    declare -a updated_configs

    case "$sync_option" in
        2)
            # Backup existing configs
            echo ""
            print_info "Existing configs will be backed up to ~/config_backup_$(date +%Y%m%d_%H%M%S)/"
            BACKUP_DIR="$HOME/config_backup_$(date +%Y%m%d_%H%M%S)"
            mkdir -p "$BACKUP_DIR"

            for item in $selected; do
                for config in "${available_configs[@]}"; do
                    IFS='|' read -r key source dest desc <<< "$config"
                    if [ "$key" = "$item" ]; then
                        # Backup if exists
                        if [ -e "$dest$key" ]; then
                            cp -r "$dest$key" "$BACKUP_DIR/" 2>/dev/null && echo "  Backed up: $key"
                        fi
                        updated_configs+=("$config")
                        break
                    fi
                done
            done
            available_configs=("${updated_configs[@]}")
            ;;
        3)
            # Custom destination
            for item in $selected; do
                for config in "${available_configs[@]}"; do
                    IFS='|' read -r key source dest desc <<< "$config"
                    if [ "$key" = "$item" ]; then
                        echo ""
                        echo "Config: $desc"
                        echo "Default destination: $dest"
                        echo -n "Enter custom destination (or press Enter to use default): "
                        read custom_dest

                        if [ -n "$custom_dest" ]; then
                            custom_dest="${custom_dest/#\~/$HOME}"
                            [[ "$custom_dest" != */ ]] && custom_dest="${custom_dest}/"
                            echo "Will sync to: $custom_dest"
                            updated_configs+=("$key|$source|$custom_dest|$desc")
                        else
                            updated_configs+=("$config")
                        fi
                        break
                    fi
                done
            done
            available_configs=("${updated_configs[@]}")
            ;;
        *)
            # Default - no changes needed
            ;;
    esac

    # Show dry run summary
    echo ""
    echo "=========================================="
    echo "  SYNC SUMMARY"
    echo "=========================================="
    echo ""
    echo "The following configuration files will be SYNCED:"
    echo ""

    for item in $selected; do
        for config in "${available_configs[@]}"; do
            IFS='|' read -r key source dest desc <<< "$config"
            if [ "$key" = "$item" ]; then
                echo "- $desc"
                echo "  From: $source"
                echo "  To: $dest"
                echo ""
                break
            fi
        done
    done

    echo "Existing files will be overwritten if different."
    echo ""

    if ! ask_yes_no "Proceed with sync?"; then
        return
    fi

    # Perform sync
    echo ""
    echo "=========================================="
    echo "  Syncing Configuration Files"
    echo "=========================================="
    echo ""

    local success_count=0
    local fail_count=0

    for item in $selected; do
        # Find config details
        for config in "${available_configs[@]}"; do
            IFS='|' read -r key source dest desc <<< "$config"
            if [ "$key" = "$item" ]; then
                if sync_item "$SOURCE_USER" "$SOURCE_HOST" "$source" "$dest" "$desc"; then
                    SELECTED_SYNC_ITEMS+=("$desc")
                    ((success_count++))
                else
                    ((fail_count++))
                fi
                echo ""
                break
            fi
        done
    done

    # Fix SSH permissions if synced
    if echo "$selected" | grep -q ".ssh"; then
        if [ -d "$DEST_HOME/.ssh" ]; then
            print_info "Fixing SSH directory permissions..."
            chmod 700 "$DEST_HOME/.ssh"
            chmod 600 "$DEST_HOME/.ssh/"* 2>/dev/null
            chmod 644 "$DEST_HOME/.ssh/"*.pub 2>/dev/null
            print_success "SSH permissions fixed"
        fi
    fi

    # Show results
    local result="Configuration Sync Complete!\n\n"
    result+="Successfully synced: $success_count files\n"
    [ $fail_count -gt 0 ] && result+="Failed: $fail_count files\n"

    if echo "$selected" | grep -q "bashrc\|bash_aliases"; then
        result+="\nTip: Run 'source ~/.bashrc' to apply changes"
    fi

    show_msgbox "Sync Results" "$result"
}

# Menu option: Sync Browser Data
menu_sync_browsers() {
    if [ $DISCOVERY_DONE -eq 0 ]; then
        show_msgbox "Error" "Please run 'Discover & Show Available Items' first!"
        return
    fi

    # Check if any browsers found
    if [ ${#BROWSERS[@]} -eq 0 ]; then
        show_msgbox "Info" "No browsers found on source laptop!"
        return
    fi

    # Build list of available browsers
    declare -a available_browsers
    declare -a checklist_options

    for browser in "${!BROWSERS[@]}"; do
        IFS='|' read -r type path <<< "${BROWSERS[$browser]}"

        # Determine destination path
        local dest_path=""
        case "$browser" in
            firefox)
                if [ "$type" = "snap" ]; then
                    dest_path="$DEST_HOME/snap/firefox/common/.mozilla/firefox/"
                else
                    dest_path="$DEST_HOME/.mozilla/firefox/"
                fi
                ;;
            google-chrome)
                dest_path="$DEST_HOME/.config/google-chrome/"
                ;;
            chromium)
                if [ "$type" = "snap" ]; then
                    dest_path="$DEST_HOME/snap/chromium/common/.config/chromium/"
                else
                    dest_path="$DEST_HOME/.config/chromium/"
                fi
                ;;
            brave)
                dest_path="$DEST_HOME/.config/BraveSoftware/"
                ;;
        esac

        available_browsers+=("$browser|$type|$path|$dest_path")
        checklist_options+=("$browser" "$browser ($type) - Bookmarks, Extensions, Passwords" "OFF")
    done

    # Show checklist
    local selected=$(show_checklist "Sync Browser Data" "Select browsers to sync (WARNING: Contains passwords):" "${checklist_options[@]}")

    # Check if user cancelled or selected nothing
    if [ -z "$selected" ]; then
        return
    fi

    # Parse selected items
    selected=$(echo "$selected" | tr -d '"')

    # Ask if user wants to customize destination paths
    echo ""
    if ask_yes_no "Do you want to customize destination paths? (default: standard browser locations)"; then
        # Update destinations with custom paths
        declare -a updated_browsers
        for item in $selected; do
            for browser_data in "${available_browsers[@]}"; do
                IFS='|' read -r name type source dest <<< "$browser_data"
                if [ "$name" = "$item" ]; then
                    echo ""
                    echo "Browser: $name ($type)"
                    echo "Default destination: $dest"
                    echo -n "Enter custom destination (or press Enter to use default): "
                    read custom_dest

                    if [ -n "$custom_dest" ]; then
                        # Expand ~ to home directory
                        custom_dest="${custom_dest/#\~/$HOME}"
                        echo "Will sync to: $custom_dest"
                        updated_browsers+=("$name|$type|$source|$custom_dest")
                    else
                        updated_browsers+=("$browser_data")
                    fi
                    break
                fi
            done
        done
        available_browsers=("${updated_browsers[@]}")
    fi

    # Show dry run summary
    echo ""
    echo "=========================================="
    echo "  SYNC SUMMARY"
    echo "=========================================="
    echo ""
    echo "The following browser data will be SYNCED:"
    echo ""

    for item in $selected; do
        for browser_data in "${available_browsers[@]}"; do
            IFS='|' read -r name type source dest <<< "$browser_data"
            if [ "$name" = "$item" ]; then
                echo "- $name ($type)"
                echo "  Profile data (bookmarks, extensions, passwords)"
                echo "  From: $source"
                echo "  To: $dest"
                echo ""
                break
            fi
        done
    done

    echo "WARNING: This includes saved passwords!"
    echo "Existing browser data will be overwritten."
    echo ""

    if ! ask_yes_no "Proceed with sync?"; then
        return
    fi

    # Perform sync
    echo ""
    echo "=========================================="
    echo "  Syncing Browser Data"
    echo "=========================================="
    echo ""

    local success_count=0
    local fail_count=0

    for item in $selected; do
        # Find browser details
        for browser_data in "${available_browsers[@]}"; do
            IFS='|' read -r name type source dest <<< "$browser_data"
            if [ "$name" = "$item" ]; then
                if sync_item "$SOURCE_USER" "$SOURCE_HOST" "$source" "$dest" "$name browser profile ($type)"; then
                    SELECTED_SYNC_ITEMS+=("$name browser profile")
                    ((success_count++))
                else
                    ((fail_count++))
                fi
                echo ""
                break
            fi
        done
    done

    # Show results
    local result="Browser Sync Complete!\n\n"
    result+="Successfully synced: $success_count browsers\n"
    [ $fail_count -gt 0 ] && result+="Failed: $fail_count browsers\n"
    result+="\nRestart your browsers to see the changes."

    show_msgbox "Sync Results" "$result"
}

# Menu option: Backup & Restore Databases
menu_backup_databases() {
    if [ $DISCOVERY_DONE -eq 0 ]; then
        show_msgbox "Error" "Please run 'Discover & Show Available Items' first!"
        return
    fi

    # Check if any database clients found
    local db_found=0
    for db in "${!DB_CLIENTS[@]}"; do
        IFS='|' read -r type info <<< "${DB_CLIENTS[$db]}"
        if [ "$type" = "installed" ]; then
            db_found=1
            break
        fi
    done

    if [ $db_found -eq 0 ]; then
        echo ""
        echo "No database clients found on source laptop!"
        echo ""
        echo "Press Enter to continue..."
        read
        return
    fi

    echo ""
    echo "=========================================="
    echo "  Database Data & Configuration Sync"
    echo "=========================================="
    echo ""
    echo "This will sync database data directories and configs."
    echo "No authentication needed - copies raw data files."
    echo ""
    echo "WARNING: Stop all database services before syncing!"
    echo "         Otherwise data may be corrupted."
    echo ""

    if ! ask_yes_no "Have you stopped database services on BOTH laptops?"; then
        echo ""
        echo "Please stop database services first:"
        echo "  PostgreSQL: sudo systemctl stop postgresql"
        echo "  MySQL:      sudo systemctl stop mysql"
        echo "  MongoDB:    sudo systemctl stop mongod"
        echo ""
        echo "Press Enter to continue..."
        read
        return
    fi

    # Array to store selected items
    declare -a selected_items

    echo ""

    # PostgreSQL
    if [ -n "${DB_CLIENTS[postgresql]}" ]; then
        if ask_yes_no "Sync PostgreSQL data directory and configs?"; then
            selected_items+=("postgresql|/var/lib/postgresql/|PostgreSQL Data")
            # Also sync config files if they exist
            if [ -n "${DB_CLIENTS[postgresql-pgpass]}" ]; then
                selected_items+=("postgresql-pgpass|${DB_CLIENTS[postgresql-pgpass]#*|}|PostgreSQL .pgpass")
            fi
            if [ -n "${DB_CLIENTS[postgresql-psqlrc]}" ]; then
                selected_items+=("postgresql-psqlrc|${DB_CLIENTS[postgresql-psqlrc]#*|}|PostgreSQL .psqlrc")
            fi
        fi
    fi

    # MySQL
    if [ -n "${DB_CLIENTS[mysql]}" ]; then
        if ask_yes_no "Sync MySQL data directory and configs?"; then
            selected_items+=("mysql|/var/lib/mysql/|MySQL Data")
            # Also sync config file if exists
            if [ -n "${DB_CLIENTS[mysql-config]}" ]; then
                selected_items+=("mysql-config|${DB_CLIENTS[mysql-config]#*|}|MySQL .my.cnf")
            fi
        fi
    fi

    # MongoDB
    if [ -n "${DB_CLIENTS[mongodb]}" ]; then
        if ask_yes_no "Sync MongoDB data directory and configs?"; then
            selected_items+=("mongodb|/var/lib/mongodb/|MongoDB Data")
            # Also sync config file if exists
            if [ -n "${DB_CLIENTS[mongodb-config]}" ]; then
                selected_items+=("mongodb-config|${DB_CLIENTS[mongodb-config]#*|}|MongoDB .mongorc.js")
            fi
        fi
    fi

    # DBeaver
    if [ -n "${DB_CLIENTS[dbeaver-data]}" ]; then
        if ask_yes_no "Sync DBeaver connections and configurations?"; then
            IFS='|' read -r type path <<< "${DB_CLIENTS[dbeaver-data]}"
            selected_items+=("dbeaver|$path|DBeaver Data")
        fi
    fi

    # Check if any items were selected
    if [ ${#selected_items[@]} -eq 0 ]; then
        echo ""
        print_warning "No database items selected for sync"
        echo ""
        echo "Press Enter to continue..."
        read
        return
    fi

    # Show dry run summary
    echo ""
    echo "=========================================="
    echo "  SYNC SUMMARY"
    echo "=========================================="
    echo ""
    echo "The following will be SYNCED:"
    echo ""

    for item in "${selected_items[@]}"; do
        IFS='|' read -r key path desc <<< "$item"
        echo "  - $desc"
        echo "    From: $SOURCE_USER@$SOURCE_HOST:$path"
    done

    echo ""
    echo "WARNING: Database data directories require sudo access!"
    echo ""

    if ! ask_yes_no "Proceed with sync?"; then
        return
    fi

    # Perform sync
    echo ""
    echo "=========================================="
    echo "  Syncing Database Data & Configs"
    echo "=========================================="
    echo ""

    local success_count=0
    local fail_count=0

    for item in "${selected_items[@]}"; do
        IFS='|' read -r key source_path desc <<< "$item"
        echo ""
        print_info "Syncing: $desc"

        # Check if this is a system directory (requires sudo)
        if [[ "$source_path" == /var/lib/* ]]; then
            print_info "This requires sudo access on BOTH laptops..."

            # Create temp directory on source
            local temp_dir="$SOURCE_HOME/db_sync_temp_$key"
            print_info "Creating temporary copy on source laptop..."

            if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "sudo cp -r $source_path $temp_dir && sudo chown -R $SOURCE_USER:$SOURCE_USER $temp_dir" 2>/dev/null; then
                # Sync from temp directory
                local dest_temp="$DEST_HOME/db_sync_temp_$key"
                if rsync_cmd -avh --progress "$SOURCE_USER@$SOURCE_HOST:$temp_dir/" "$dest_temp/"; then
                    # Move to final location with sudo
                    print_info "Moving to system directory (requires sudo password)..."
                    if sudo cp -r "$dest_temp"/* "$source_path/" 2>/dev/null; then
                        print_success "Successfully synced: $desc"
                        ((success_count++))
                        SELECTED_DB_BACKUPS+=("$desc")

                        # Cleanup
                        rm -rf "$dest_temp"
                        ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "rm -rf $temp_dir"
                    else
                        print_error "Failed to move to system directory: $desc"
                        ((fail_count++))
                    fi
                else
                    print_error "Failed to transfer: $desc"
                    ((fail_count++))
                fi
            else
                print_error "Failed to create temp copy on source: $desc"
                ((fail_count++))
            fi
        else
            # Regular file/directory sync (user-owned)
            if sync_item "$SOURCE_USER" "$SOURCE_HOST" "$source_path" "$DEST_HOME/" "$desc"; then
                SELECTED_DB_BACKUPS+=("$desc")
                ((success_count++))
            else
                ((fail_count++))
            fi
        fi
        echo ""
    done

    # Show results
    echo ""
    echo "=========================================="
    echo "Database Sync Complete!"
    echo "=========================================="
    echo ""
    echo "Successfully synced: $success_count items"
    [ $fail_count -gt 0 ] && echo "Failed: $fail_count items"
    echo ""
    echo "IMPORTANT: Restart database services:"
    echo "  sudo systemctl start postgresql"
    echo "  sudo systemctl start mysql"
    echo "  sudo systemctl start mongod"
    echo ""
    echo "Press Enter to continue..."
    read
}

# Menu option: Sync Development Tools Config
menu_sync_dev_tools() {
    if [ $DISCOVERY_DONE -eq 0 ]; then
        show_msgbox "Error" "Please run 'Discover & Show Available Items' first!"
        return
    fi

    # Build list of available dev tool configs
    declare -a available_configs
    declare -a checklist_options

    # VSCode
    if [ -n "${DEV_TOOLS[vscode-config]}" ]; then
        IFS='|' read -r type path <<< "${DEV_TOOLS[vscode-config]}"
        available_configs+=("vscode|$path|$DEST_HOME/.config/|VSCode Settings & Extensions")
        checklist_options+=("vscode" "VSCode - Settings & Extensions" "OFF")
    fi

    # Docker
    if [ -n "${DEV_TOOLS[docker-config]}" ]; then
        IFS='|' read -r type path <<< "${DEV_TOOLS[docker-config]}"
        available_configs+=("docker|$path|$DEST_HOME/|Docker Configuration")
        checklist_options+=("docker" "Docker Configuration" "OFF")
    fi

    # npm
    if [ -n "${DEV_TOOLS[npm-config]}" ]; then
        IFS='|' read -r type path <<< "${DEV_TOOLS[npm-config]}"
        available_configs+=("npm|$path|$DEST_HOME/|npm Configuration")
        checklist_options+=("npm" "npm Configuration (.npmrc)" "OFF")
    fi

    # Git config (from home directory)
    if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "test -f $SOURCE_HOME/.gitconfig" 2>/dev/null; then
        available_configs+=("git|$SOURCE_HOME/.gitconfig|$DEST_HOME/|Git Configuration (.gitconfig)")
        checklist_options+=("git" "Git Configuration (.gitconfig)" "OFF")
    fi

    # Python pip config
    if [ -n "${DEV_TOOLS[python3]}" ]; then
        if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "test -f $SOURCE_HOME/.pip/pip.conf || test -d $SOURCE_HOME/.local/pipx" 2>/dev/null; then
            available_configs+=("python|$SOURCE_HOME/.pip/|$DEST_HOME/|Python pip Configuration" "python-pipx|$SOURCE_HOME/.local/pipx/|$DEST_HOME/.local/|Python pipx packages")
            checklist_options+=("python" "Python Configuration (pip/pipx)" "OFF")
        fi
    fi

    # Node.js/nvm
    if [ -n "${DEV_TOOLS[nodejs]}" ]; then
        if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "test -d $SOURCE_HOME/.nvm" 2>/dev/null; then
            available_configs+=("nvm|$SOURCE_HOME/.nvm/|$DEST_HOME/|Node Version Manager (nvm)")
            checklist_options+=("nvm" "Node Version Manager (nvm)" "OFF")
        fi
    fi

    # Cargo/Rust config
    if ssh_cmd "$SOURCE_USER@$SOURCE_HOST" "test -d $SOURCE_HOME/.cargo" 2>/dev/null; then
        available_configs+=("cargo|$SOURCE_HOME/.cargo/|$DEST_HOME/|Rust/Cargo Configuration")
        checklist_options+=("cargo" "Rust/Cargo Configuration" "OFF")
    fi

    # Check if any configs are available
    if [ ${#available_configs[@]} -eq 0 ]; then
        show_msgbox "Info" "No development tool configurations found on source laptop!"
        return
    fi

    # Show checklist
    local selected=$(show_checklist "Sync Dev Tools Config" "Select development tool configurations to sync:" "${checklist_options[@]}")

    if [ -z "$selected" ]; then
        return
    fi

    selected=$(echo "$selected" | tr -d '"')

    # Show dry run summary
    local summary="The following configurations will be SYNCED:\n\n"
    for item in $selected; do
        for config in "${available_configs[@]}"; do
            IFS='|' read -r key source dest desc <<< "$config"
            if [ "$key" = "$item" ]; then
                summary+="- $desc\n"
                break
            fi
        done
    done

    summary+="\nProceed with sync?"

    if ! ask_yes_no "$summary"; then
        return
    fi

    # Perform sync
    echo ""
    echo "=========================================="
    echo "  Syncing Development Tool Configurations"
    echo "=========================================="
    echo ""

    local success_count=0
    local fail_count=0

    for item in $selected; do
        for config in "${available_configs[@]}"; do
            IFS='|' read -r key source dest desc <<< "$config"
            if [ "$key" = "$item" ]; then
                if sync_item "$SOURCE_USER" "$SOURCE_HOST" "$source" "$dest" "$desc"; then
                    SELECTED_SYNC_ITEMS+=("$desc")
                    ((success_count++))
                else
                    ((fail_count++))
                fi
                echo ""
                break
            fi
        done
    done

    echo ""
    echo "=========================================="
    echo "Dev Tools Sync Complete!"
    echo "=========================================="
    echo ""
    echo "Successfully synced: $success_count configs"
    [ $fail_count -gt 0 ] && echo "Failed: $fail_count configs"
    echo ""
    echo "Press Enter to continue..."
    read
}

# Menu option: Sync User Directories
menu_sync_user_dirs() {
    if [ $DISCOVERY_DONE -eq 0 ]; then
        show_msgbox "Error" "Please run 'Discover & Show Available Items' first!"
        return
    fi

    # Common user directories
    declare -a common_dirs=("Documents" "Downloads" "Desktop" "Pictures" "Videos" "Music" "workspace" "projects" "dev")
    declare -a available_dirs
    declare -a checklist_options

    # Check which common directories exist
    for dir in "${common_dirs[@]}"; do
        if echo "$DISCOVERED_DIRS" | grep -q "^${dir}$"; then
            available_dirs+=("$dir|$SOURCE_HOME/$dir|$DEST_HOME/")
            checklist_options+=("$dir" "$dir folder" "OFF")
        fi
    done

    if [ ${#available_dirs[@]} -eq 0 ]; then
        show_msgbox "Info" "No common user directories found on source laptop!\n\nUse 'Sync Custom Directory' to sync other folders."
        return
    fi

    # Show checklist
    local selected=$(show_checklist "Sync User Directories" "Select directories to sync:" "${checklist_options[@]}")

    if [ -z "$selected" ]; then
        return
    fi

    selected=$(echo "$selected" | tr -d '"')

    # Ask if user wants to customize destination paths
    echo ""
    if ask_yes_no "Do you want to customize destination paths? (default: ~/DirectoryName)"; then
        # Update destinations with custom paths
        declare -a updated_dirs
        for item in $selected; do
            for dir_data in "${available_dirs[@]}"; do
                IFS='|' read -r name source dest <<< "$dir_data"
                if [ "$name" = "$item" ]; then
                    echo ""
                    echo "Directory: $name"
                    echo "Default destination: ${dest}${name}"
                    echo -n "Enter custom destination (or press Enter to use default): "
                    read custom_dest

                    if [ -n "$custom_dest" ]; then
                        # Expand ~ to home directory
                        custom_dest="${custom_dest/#\~/$HOME}"
                        # Ensure trailing slash
                        [[ "$custom_dest" != */ ]] && custom_dest="${custom_dest}/"
                        echo "Will sync to: $custom_dest"
                        updated_dirs+=("$name|$source|$custom_dest")
                    else
                        updated_dirs+=("$dir_data")
                    fi
                    break
                fi
            done
        done
        available_dirs=("${updated_dirs[@]}")
    fi

    # Show dry run summary
    echo ""
    echo "=========================================="
    echo "  SYNC SUMMARY"
    echo "=========================================="
    echo ""
    echo "The following directories will be SYNCED:"
    echo ""

    for item in $selected; do
        for dir_data in "${available_dirs[@]}"; do
            IFS='|' read -r name source dest <<< "$dir_data"
            if [ "$name" = "$item" ]; then
                echo "- $name"
                echo "  From: $source"
                echo "  To: $dest"
                echo ""
                break
            fi
        done
    done

    echo "WARNING: This may transfer large amounts of data!"
    echo ""

    if ! ask_yes_no "Proceed with sync?"; then
        return
    fi

    # Perform sync
    echo ""
    echo "=========================================="
    echo "  Syncing User Directories"
    echo "=========================================="
    echo ""

    local success_count=0
    local fail_count=0

    for item in $selected; do
        for dir_data in "${available_dirs[@]}"; do
            IFS='|' read -r name source dest <<< "$dir_data"
            if [ "$name" = "$item" ]; then
                if sync_item "$SOURCE_USER" "$SOURCE_HOST" "$source" "$dest" "$name folder"; then
                    SELECTED_SYNC_ITEMS+=("$name folder")
                    ((success_count++))
                else
                    ((fail_count++))
                fi
                echo ""
                break
            fi
        done
    done

    local result="User Directories Sync Complete!\n\n"
    result+="Successfully synced: $success_count directories\n"
    [ $fail_count -gt 0 ] && result+="Failed: $fail_count directories\n"

    show_msgbox "Sync Results" "$result"
}

# Menu option: Sync Custom Directory
menu_sync_custom_dir() {
    if [ $DISCOVERY_DONE -eq 0 ]; then
        show_msgbox "Error" "Please run 'Discover & Show Available Items' first!"
        return
    fi

    # Get custom paths
    if [ "$DIALOG" != "none" ]; then
        local source_path=$(whiptail --title "Custom Directory" --inputbox "Enter source path (absolute or relative to $SOURCE_HOME):" 10 70 3>&1 1>&2 2>&3)
        [ -z "$source_path" ] && return

        local dest_path=$(whiptail --title "Custom Directory" --inputbox "Enter destination path (absolute or relative to $DEST_HOME):" 10 70 "$DEST_HOME/" 3>&1 1>&2 2>&3)
        [ -z "$dest_path" ] && return
    else
        echo ""
        read -p "Enter source path (absolute or relative to $SOURCE_HOME): " source_path
        [ -z "$source_path" ] && return

        read -p "Enter destination path (absolute or relative to $DEST_HOME): " dest_path
        [ -z "$dest_path" ] && return
    fi

    # Handle relative paths
    if [[ "$source_path" != /* ]]; then
        source_path="$SOURCE_HOME/$source_path"
    fi
    if [[ "$dest_path" != /* ]]; then
        dest_path="$DEST_HOME/$dest_path"
    fi

    # Show dry run summary
    local summary="Custom directory will be SYNCED:\n\n"
    summary+="From: $source_path\n"
    summary+="To: $dest_path\n\n"
    summary+="Proceed with sync?"

    if ! ask_yes_no "$summary"; then
        return
    fi

    # Perform sync
    echo ""
    echo "=========================================="
    echo "  Syncing Custom Directory"
    echo "=========================================="
    echo ""

    if sync_item "$SOURCE_USER" "$SOURCE_HOST" "$source_path" "$dest_path" "Custom directory"; then
        SELECTED_SYNC_ITEMS+=("Custom: $source_path")
        show_msgbox "Success" "Custom directory synced successfully!"
    else
        show_msgbox "Error" "Failed to sync custom directory!"
    fi
}

execute_all_operations() {
    if [ ${#SELECTED_SYNC_ITEMS[@]} -eq 0 ] && [ ${#SELECTED_APPS_TO_INSTALL[@]} -eq 0 ] && [ ${#SELECTED_DB_BACKUPS[@]} -eq 0 ]; then
        show_msgbox "Error" "No operations selected!\n\nPlease select items to sync from the menu options."
        return
    fi

    show_msgbox "Coming Soon" "Execute All Operations feature will be implemented here."
}

view_selections() {
    local summary="CURRENT SELECTIONS\n\n"

    if [ ${#SELECTED_APPS_TO_INSTALL[@]} -gt 0 ]; then
        summary+="=== APPLICATIONS TO INSTALL ===\n"
        for app in "${SELECTED_APPS_TO_INSTALL[@]}"; do
            summary+="- $app\n"
        done
        summary+="\n"
    fi

    if [ ${#SELECTED_SYNC_ITEMS[@]} -gt 0 ]; then
        summary+="=== ITEMS TO SYNC ===\n"
        for item in "${SELECTED_SYNC_ITEMS[@]}"; do
            summary+="- $item\n"
        done
        summary+="\n"
    fi

    if [ ${#SELECTED_DB_BACKUPS[@]} -gt 0 ]; then
        summary+="=== DATABASES TO BACKUP ===\n"
        for db in "${SELECTED_DB_BACKUPS[@]}"; do
            summary+="- $db\n"
        done
        summary+="\n"
    fi

    if [ ${#SELECTED_APPS_TO_INSTALL[@]} -eq 0 ] && [ ${#SELECTED_SYNC_ITEMS[@]} -eq 0 ] && [ ${#SELECTED_DB_BACKUPS[@]} -eq 0 ]; then
        summary="No items selected yet.\n\nUse the menu options to select items for sync."
    fi

    show_msgbox "Current Selections" "$summary"
}

clear_selections() {
    if ask_yes_no "Are you sure you want to clear all selections?"; then
        SELECTED_APPS_TO_INSTALL=()
        SELECTED_SYNC_ITEMS=()
        SELECTED_DB_BACKUPS=()
        show_msgbox "Success" "All selections cleared!"
    fi
}

# Main script
main() {
    clear
    echo "=========================================="
    echo "  Ubuntu Laptop Sync Script"
    echo "=========================================="
    echo ""

    if [ $NO_GUI -eq 0 ]; then
        echo "Make sure your old laptop is ssh accessible & firewall allows ssh"
        echo "=========================================="
        echo "Run following command on OLD laptop to enable ssh"
        echo "  sudo apt install openssh-server"
        echo "  sudo systemctl enable --now ssh"
        echo ""
        echo "To enable firewall access:"
        echo "  sudo ufw allow ssh"
        echo ""
        echo "To check IP address, run:"
        echo "  hostname -I"
        echo ""
        echo "You will need the username, IP address & password of the OLD laptop"
        echo "=========================================="
        echo ""
        echo "USAGE TIP: When you see checkboxes:"
        echo "  - Use SPACE to select/deselect items"
        echo "  - Use ARROW KEYS to navigate"
        echo "  - Press ENTER when done"
        echo ""
        echo "For yes/no prompts:"
        echo "  - Type 'y' for yes, 'n' for no"
        echo ""
        echo "Press Enter to continue..."
        read
    else
        echo "Running in TERMINAL-ONLY mode"
        echo ""
        echo "Benefits:"
        echo "  ✓ See all rsync progress in real-time"
        echo "  ✓ Full terminal logs visible"
        echo "  ✓ No dialog boxes"
        echo ""
        echo "To use GUI mode, run without --no-gui flag"
        echo ""
        echo "Press Enter to continue..."
        read
    fi

    # Check if rsync is installed
    check_rsync

    # Check if sshpass is available (optional)
    check_sshpass

    # Show main menu
    main_menu
}

# Run main function
main
