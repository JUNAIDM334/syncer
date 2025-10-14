#!/bin/bash

# Database Sync Module
# Syncs database data directories and config files directly (no dumps)
# Note: utils.sh and ssh.sh are sourced by the main script

# Default database data directory mappings (will be auto-detected)
declare -A DB_DATA_DIRS=(
    ["postgresql"]="/var/lib/postgresql"
    ["mysql"]="/var/lib/mysql"
    ["mongodb"]="/var/lib/mongodb"
    ["redis"]="/var/lib/redis"
)

# Detect actual database data directory on source
detect_db_data_dir() {
    local source_user="$1"
    local source_host="$2"
    local db="$3"

    local possible_dirs=()

    case "$db" in
        postgresql)
            possible_dirs=(
                "/var/lib/postgresql"
                "/var/snap/postgresql/common"
                "/var/lib/pgsql"
            )
            ;;
        mysql)
            possible_dirs=(
                "/var/lib/mysql"
                "/var/snap/mysql/common/data"
                "/var/lib/mysql-files"
            )
            ;;
        mongodb)
            possible_dirs=(
                "/var/lib/mongodb"
                "/var/lib/mongo"
                "/var/snap/mongodb/common"
            )
            ;;
        redis)
            possible_dirs=(
                "/var/lib/redis"
                "/var/snap/redis/common"
            )
            ;;
    esac

    # Try to find the actual data directory
    for dir in "${possible_dirs[@]}"; do
        if ssh_cmd "$source_user@$source_host" "sudo test -d $dir 2>/dev/null && sudo test -n \"\$(sudo ls -A $dir 2>/dev/null)\""; then
            echo "$dir"
            return 0
        fi
    done

    # If not found, ask the user
    return 1
}

# Database config file mappings (user-level)
declare -A DB_CONFIG_FILES=(
    ["postgresql-pgpass"]="$HOME/.pgpass"
    ["postgresql-psqlrc"]="$HOME/.psqlrc"
    ["mysql-mycnf"]="$HOME/.my.cnf"
    ["mongodb-mongorc"]="$HOME/.mongorc.js"
    ["dbeaver-data"]="$HOME/.local/share/DBeaverData"
)

# Database system config file mappings (require sudo)
declare -A DB_SYSTEM_CONFIGS=(
    ["postgresql-system-config"]="/etc/postgresql"
    ["mysql-system-config"]="/etc/mysql"
    ["mongodb-system-config"]="/etc/mongod.conf"
    ["redis-system-config"]="/etc/redis/redis.conf"
)

# Check if database service is running
is_db_service_running() {
    local db="$1"
    local service_name=""

    case "$db" in
        postgresql) service_name="postgresql" ;;
        mysql) service_name="mysql" ;;
        mongodb) service_name="mongod" ;;
        redis) service_name="redis-server" ;;
        *) return 1 ;;
    esac

    systemctl is-active --quiet "$service_name" 2>/dev/null
}

# Stop database service
stop_db_service() {
    local db="$1"
    local service_name=""

    case "$db" in
        postgresql) service_name="postgresql" ;;
        mysql) service_name="mysql" ;;
        mongodb) service_name="mongod" ;;
        redis) service_name="redis-server" ;;
        *) return 1 ;;
    esac

    print_info "Stopping $service_name service..."
    if sudo systemctl stop "$service_name" 2>/dev/null; then
        print_success "$service_name stopped"
        return 0
    else
        print_warning "Failed to stop $service_name (might not be installed)"
        return 1
    fi
}

# Start database service
start_db_service() {
    local db="$1"
    local service_name=""

    case "$db" in
        postgresql) service_name="postgresql" ;;
        mysql) service_name="mysql" ;;
        mongodb) service_name="mongod" ;;
        redis) service_name="redis-server" ;;
        *) return 1 ;;
    esac

    print_info "Starting $service_name service..."
    if sudo systemctl start "$service_name" 2>/dev/null; then
        print_success "$service_name started"
        return 0
    else
        print_error "Failed to start $service_name"
        return 1
    fi
}

# Sync database data directory
sync_db_data_dir() {
    local source_user="$1"
    local source_host="$2"
    local db="$3"

    # Try to detect actual data directory
    print_info "Detecting $db data directory on source..."
    local data_dir=$(detect_db_data_dir "$source_user" "$source_host" "$db")

    if [ -z "$data_dir" ]; then
        print_warning "Could not auto-detect $db data directory"
        print_info "Please enter the data directory path on source laptop (or press Enter to skip):"
        read -p "Path: " data_dir

        if [ -z "$data_dir" ]; then
            print_warning "Skipping $db data sync"
            return 0
        fi

        # Verify the path exists
        if ! ssh_cmd "$source_user@$source_host" "sudo test -d $data_dir 2>/dev/null"; then
            print_error "Directory does not exist: $data_dir"
            return 1
        fi
    else
        print_success "Found data directory: $data_dir"
    fi

    print_info "Syncing $db data from: $data_dir"
    echo ""

    # Check if database service is running on source
    print_info "Checking if $db service is running on source laptop..."
    local service_name=""
    case "$db" in
        postgresql) service_name="postgresql" ;;
        mysql) service_name="mysql" ;;
        mongodb) service_name="mongod" ;;
        redis) service_name="redis-server" ;;
    esac

    if ssh_cmd "$source_user@$source_host" "systemctl is-active --quiet $service_name 2>/dev/null"; then
        print_error "$db service is running on source laptop!"
        print_warning "You MUST stop the database service on source laptop before syncing data."
        echo ""
        print_info "Please run this command on the SOURCE laptop:"
        echo "  sudo systemctl stop $service_name"
        echo ""
        if ask_yes_no "Have you stopped the service? Continue with sync?"; then
            # Verify it's actually stopped
            if ssh_cmd "$source_user@$source_host" "systemctl is-active --quiet $service_name 2>/dev/null"; then
                print_error "$db service is still running! Aborting sync."
                return 1
            else
                print_success "$db service is stopped on source"
            fi
        else
            print_error "Cannot sync while database is running. Aborting."
            return 1
        fi
    else
        print_success "$db service is not running on source"
    fi

    # Check if database service is running locally
    if is_db_service_running "$db"; then
        print_warning "$db service is running on this laptop"
        if ask_yes_no "Stop $db service on this laptop before syncing?"; then
            stop_db_service "$db" || return 1
        else
            print_error "Cannot sync while database is running. Aborting."
            return 1
        fi
    fi

    # Verify data directory (already checked in detect, but double-check)
    print_info "Verifying source data directory..."
    local file_count=$(ssh_cmd "$source_user@$source_host" "sudo find $data_dir -type f 2>/dev/null | wc -l" 2>/dev/null)

    if [ -z "$file_count" ] || [ "$file_count" -eq "0" ]; then
        print_warning "Data directory is empty or inaccessible: $data_dir"
        print_info "This could mean:"
        echo "  - Database is installed but never initialized"
        echo "  - Different data directory is being used"
        echo "  - Permission issues preventing access"
        if ! ask_yes_no "Continue anyway?"; then
            return 1
        fi
    else
        print_success "Found $file_count files in data directory"
    fi

    # Create temporary directory on source
    local temp_dir="/tmp/db_sync_${db}_$$"
    print_info "Creating temporary copy on source laptop (requires sudo)..."

    # Create temp dir
    if ! ssh_cmd "$source_user@$source_host" "sudo mkdir -p $temp_dir 2>&1"; then
        print_error "Failed to create temporary directory: $temp_dir"
        return 1
    fi

    # Copy data
    print_info "Copying data to temporary directory..."
    if ssh_cmd "$source_user@$source_host" "sudo cp -rp $data_dir/* $temp_dir/ 2>&1"; then
        # Change ownership
        print_info "Fixing permissions..."
        if ssh_cmd "$source_user@$source_host" "sudo chown -R $source_user:$source_user $temp_dir 2>&1"; then
            print_success "Temporary copy created on source"
        else
            print_error "Failed to change ownership of temporary directory"
            ssh_cmd "$source_user@$source_host" "sudo rm -rf $temp_dir 2>/dev/null"
            return 1
        fi
    else
        print_error "Failed to copy data to temporary directory"
        ssh_cmd "$source_user@$source_host" "sudo rm -rf $temp_dir 2>/dev/null"
        return 1
    fi

    # Sync from temp directory
    local dest_temp="$HOME/db_sync_temp_${db}"
    mkdir -p "$dest_temp"

    print_info "Transferring data (this may take a while)..."
    if rsync_cmd -avh --progress "$source_user@$source_host:$temp_dir/" "$dest_temp/"; then
        print_success "Data transferred successfully"

        # Stop local service if running
        is_db_service_running "$db" && stop_db_service "$db"

        # Move to final location with sudo
        print_info "Installing data to $data_dir (requires sudo)..."
        if sudo mkdir -p "$data_dir" && sudo cp -rp "$dest_temp"/* "$data_dir/" 2>/dev/null; then
            print_success "Database data installed successfully"

            # Fix ownership based on database type
            case "$db" in
                postgresql)
                    sudo chown -R postgres:postgres "$data_dir" 2>/dev/null
                    ;;
                mysql)
                    sudo chown -R mysql:mysql "$data_dir" 2>/dev/null
                    ;;
                mongodb)
                    sudo chown -R mongodb:mongodb "$data_dir" 2>/dev/null
                    ;;
                redis)
                    sudo chown -R redis:redis "$data_dir" 2>/dev/null
                    ;;
            esac
            print_success "Permissions fixed"

            # Cleanup
            rm -rf "$dest_temp"
            ssh_cmd "$source_user@$source_host" "sudo rm -rf $temp_dir"

            # Ask to start service
            if ask_yes_no "Start $db service now?"; then
                start_db_service "$db"
            fi

            return 0
        else
            print_error "Failed to install data to $data_dir"
            rm -rf "$dest_temp"
            ssh_cmd "$source_user@$source_host" "sudo rm -rf $temp_dir"
            return 1
        fi
    else
        print_error "Failed to transfer data"
        ssh_cmd "$source_user@$source_host" "sudo rm -rf $temp_dir"
        return 1
    fi
}

# Sync database config files
sync_db_config_files() {
    local source_user="$1"
    local source_host="$2"
    local source_home="$3"
    local db_key="$4"

    # Check if it's a user-level config
    local config_file="${DB_CONFIG_FILES[$db_key]}"
    if [ -n "$config_file" ]; then
        # User-level config - sync normally
        local source_path=""
        case "$db_key" in
            postgresql-pgpass) source_path="$source_home/.pgpass" ;;
            postgresql-psqlrc) source_path="$source_home/.psqlrc" ;;
            mysql-mycnf) source_path="$source_home/.my.cnf" ;;
            mongodb-mongorc) source_path="$source_home/.mongorc.js" ;;
            dbeaver-data) source_path="$source_home/.local/share/DBeaverData" ;;
        esac

        if [ -n "$source_path" ]; then
            sync_item "$source_user" "$source_host" "$source_path" "$HOME/" "$db_key config"
            return $?
        fi
    fi

    # Check if it's a system-level config
    local system_config="${DB_SYSTEM_CONFIGS[$db_key]}"
    if [ -n "$system_config" ]; then
        print_info "Syncing system config: $system_config"

        # Create temp directory
        local temp_dir="$HOME/db_config_sync_$$"
        mkdir -p "$temp_dir"

        # Sync from source
        if rsync_cmd -avh --progress --rsync-path="sudo rsync" "$source_user@$source_host:$system_config" "$temp_dir/"; then
            print_success "Config downloaded"

            # Install with sudo
            print_info "Installing system config (requires sudo)..."
            local dest_dir=$(dirname "$system_config")
            if sudo mkdir -p "$dest_dir" && sudo cp -rp "$temp_dir"/* "$dest_dir"/; then
                print_success "System config installed: $system_config"
                rm -rf "$temp_dir"
                return 0
            else
                print_error "Failed to install system config"
                rm -rf "$temp_dir"
                return 1
            fi
        else
            print_error "Failed to download system config"
            rm -rf "$temp_dir"
            return 1
        fi
    fi

    print_warning "No config file mapping for: $db_key"
    return 1
}

# Interactive database sync selection
select_databases_to_sync() {
    local source_user="$1"
    local source_host="$2"
    local source_home="$3"

    if [ ${#DB_CLIENTS[@]} -eq 0 ]; then
        print_warning "No database clients discovered"
        return
    fi

    echo ""
    print_info "=== Database Data & Configuration Sync ==="
    echo ""

    print_warning "IMPORTANT: This will copy database data directories directly"
    print_warning "Database services will be stopped during sync to prevent corruption"
    echo ""

    declare -a selected_dbs

    # PostgreSQL
    if [ -n "${DB_CLIENTS[postgresql]}" ]; then
        echo "PostgreSQL detected"

        # Check if installed locally
        if ! is_database_installed "postgresql"; then
            print_warning "PostgreSQL is not installed on this laptop"
            if ask_yes_no "Install PostgreSQL?"; then
                if install_application "postgresql"; then
                    print_success "PostgreSQL installed"
                else
                    print_error "Failed to install PostgreSQL"
                fi
            fi
        fi

        if ask_yes_no "Sync PostgreSQL data directory and config files?"; then
            selected_dbs+=("postgresql")

            # Automatically include config files if they exist
            if [ -n "${DB_CLIENTS[postgresql-pgpass]}" ]; then
                SYNC_ITEMS+=("postgresql-pgpass")
                print_success "Will sync PostgreSQL .pgpass file"
            fi
            if [ -n "${DB_CLIENTS[postgresql-psqlrc]}" ]; then
                SYNC_ITEMS+=("postgresql-psqlrc")
                print_success "Will sync PostgreSQL .psqlrc file"
            fi

            # Also sync system config if exists
            if ssh_cmd "$source_user@$source_host" "test -f /etc/postgresql/postgresql.conf 2>/dev/null"; then
                print_success "Will sync system PostgreSQL config"
                SYNC_ITEMS+=("postgresql-system-config")
            fi
        fi
        echo ""
    fi

    # MySQL
    if [ -n "${DB_CLIENTS[mysql]}" ]; then
        echo "MySQL/MariaDB detected"

        if ! is_database_installed "mysql"; then
            print_warning "MySQL is not installed on this laptop"
            if ask_yes_no "Install MySQL server?"; then
                if install_application "mysql"; then
                    print_success "MySQL installed"
                else
                    print_error "Failed to install MySQL"
                fi
            fi
        fi

        if ask_yes_no "Sync MySQL data directory and config files?"; then
            selected_dbs+=("mysql")

            # Automatically include config files if they exist
            if [ -n "${DB_CLIENTS[mysql-config]}" ]; then
                SYNC_ITEMS+=("mysql-mycnf")
                print_success "Will sync MySQL .my.cnf file"
            fi

            # Also sync system config if exists
            if ssh_cmd "$source_user@$source_host" "test -f /etc/mysql/my.cnf 2>/dev/null"; then
                print_success "Will sync system MySQL config"
                SYNC_ITEMS+=("mysql-system-config")
            fi
        fi
        echo ""
    fi

    # MongoDB
    if [ -n "${DB_CLIENTS[mongodb]}" ]; then
        echo "MongoDB detected"

        if ! is_database_installed "mongodb"; then
            print_warning "MongoDB is not installed on this laptop"
            if ask_yes_no "Install MongoDB?"; then
                if install_application "mongodb"; then
                    print_success "MongoDB installed"
                else
                    print_error "Failed to install MongoDB"
                fi
            fi
        fi

        if ask_yes_no "Sync MongoDB data directory and config files?"; then
            selected_dbs+=("mongodb")

            # Automatically include config files if they exist
            if [ -n "${DB_CLIENTS[mongodb-config]}" ]; then
                SYNC_ITEMS+=("mongodb-mongorc")
                print_success "Will sync MongoDB .mongorc.js file"
            fi

            # Also sync system config if exists
            if ssh_cmd "$source_user@$source_host" "test -f /etc/mongod.conf 2>/dev/null"; then
                print_success "Will sync system MongoDB config"
                SYNC_ITEMS+=("mongodb-system-config")
            fi
        fi
        echo ""
    fi

    # Redis
    if [ -n "${DB_CLIENTS[redis]}" ]; then
        echo "Redis detected"

        if ! is_database_installed "redis"; then
            print_warning "Redis is not installed on this laptop"
            if ask_yes_no "Install Redis?"; then
                if install_application "redis"; then
                    print_success "Redis installed"
                else
                    print_error "Failed to install Redis"
                fi
            fi
        fi

        if ask_yes_no "Sync Redis data directory and config?"; then
            selected_dbs+=("redis")

            # Also sync system config if exists
            if ssh_cmd "$source_user@$source_host" "test -f /etc/redis/redis.conf 2>/dev/null"; then
                print_success "Will sync system Redis config"
                SYNC_ITEMS+=("redis-system-config")
            fi
        fi
        echo ""
    fi

    # DBeaver (user-level, no system directories)
    if [ -n "${DB_CLIENTS[dbeaver-data]}" ]; then
        echo "DBeaver detected"
        if ask_yes_no "Sync DBeaver connections and data?"; then
            SYNC_ITEMS+=("dbeaver-data")
            print_success "Will sync DBeaver configuration and connections"
        fi
        echo ""
    fi

    # Export selected databases for later processing
    export SELECTED_DATABASES=("${selected_dbs[@]}")
}

# Execute database sync
execute_database_sync() {
    local source_user="$1"
    local source_host="$2"
    local source_home="$3"

    if [ ${#SELECTED_DATABASES[@]} -eq 0 ]; then
        return 0
    fi

    echo ""
    echo "=========================================="
    echo "  Syncing Database Data"
    echo "=========================================="
    echo ""

    for db in "${SELECTED_DATABASES[@]}"; do
        print_info "Processing: $db"
        echo ""
        sync_db_data_dir "$source_user" "$source_host" "$db"
        echo ""
    done

    print_success "Database sync complete!"
}
