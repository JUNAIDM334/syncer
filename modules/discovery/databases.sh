#!/bin/bash

# Database Discovery Module
# Detects installed database clients and their configurations
# Note: utils.sh and ssh.sh are sourced by the main script

# Discover database clients on remote host
discover_databases() {
    local source_user="$1"
    local source_host="$2"
    local source_home="$3"

    declare -gA DB_CLIENTS

    print_info "Detecting database clients..."

    # PostgreSQL
    if ssh_cmd "$source_user@$source_host" "command -v psql &>/dev/null" 2>/dev/null; then
        PSQL_VERSION=$(ssh_cmd "$source_user@$source_host" "psql --version 2>/dev/null | awk '{print \$3}'" 2>/dev/null)
        DB_CLIENTS["postgresql"]="installed|$PSQL_VERSION"
        echo "  ✓ PostgreSQL ($PSQL_VERSION)"
        if ssh_cmd "$source_user@$source_host" "test -f $source_home/.pgpass" 2>/dev/null; then
            DB_CLIENTS["postgresql-pgpass"]="config|$source_home/.pgpass"
        fi
        if ssh_cmd "$source_user@$source_host" "test -f $source_home/.psqlrc" 2>/dev/null; then
            DB_CLIENTS["postgresql-psqlrc"]="config|$source_home/.psqlrc"
        fi
    fi

    # MySQL/MariaDB
    if ssh_cmd "$source_user@$source_host" "command -v mysql &>/dev/null" 2>/dev/null; then
        MYSQL_VERSION=$(ssh_cmd "$source_user@$source_host" "mysql --version 2>/dev/null | awk '{print \$5}' | cut -d, -f1" 2>/dev/null)
        DB_CLIENTS["mysql"]="installed|$MYSQL_VERSION"
        echo "  ✓ MySQL/MariaDB ($MYSQL_VERSION)"
        if ssh_cmd "$source_user@$source_host" "test -f $source_home/.my.cnf" 2>/dev/null; then
            DB_CLIENTS["mysql-config"]="config|$source_home/.my.cnf"
        fi
    fi

    # MongoDB
    if ssh_cmd "$source_user@$source_host" "command -v mongosh &>/dev/null || command -v mongo &>/dev/null" 2>/dev/null; then
        MONGO_VERSION=$(ssh_cmd "$source_user@$source_host" "mongosh --version 2>/dev/null || mongo --version 2>/dev/null | head -1 | awk '{print \$4}'" 2>/dev/null)
        DB_CLIENTS["mongodb"]="installed|$MONGO_VERSION"
        echo "  ✓ MongoDB ($MONGO_VERSION)"
        if ssh_cmd "$source_user@$source_host" "test -f $source_home/.mongorc.js" 2>/dev/null; then
            DB_CLIENTS["mongodb-config"]="config|$source_home/.mongorc.js"
        fi
    fi

    # Redis
    if ssh_cmd "$source_user@$source_host" "command -v redis-cli &>/dev/null" 2>/dev/null; then
        REDIS_VERSION=$(ssh_cmd "$source_user@$source_host" "redis-cli --version 2>/dev/null | awk '{print \$2}'" 2>/dev/null)
        DB_CLIENTS["redis"]="installed|$REDIS_VERSION"
        echo "  ✓ Redis ($REDIS_VERSION)"
    fi

    # DBeaver
    if ssh_cmd "$source_user@$source_host" "command -v dbeaver &>/dev/null || test -d $source_home/.local/share/DBeaverData" 2>/dev/null; then
        DB_CLIENTS["dbeaver"]="installed|gui"
        echo "  ✓ DBeaver"
        if ssh_cmd "$source_user@$source_host" "test -d $source_home/.local/share/DBeaverData" 2>/dev/null; then
            DB_CLIENTS["dbeaver-data"]="config|$source_home/.local/share/DBeaverData/"
        fi
    fi
}

# Check if database client is installed locally
is_database_installed() {
    local db="$1"
    case "$db" in
        postgresql) command -v psql &>/dev/null ;;
        mysql) command -v mysql &>/dev/null ;;
        mongodb) command -v mongosh &>/dev/null || command -v mongo &>/dev/null ;;
        redis) command -v redis-cli &>/dev/null ;;
        dbeaver) command -v dbeaver &>/dev/null ;;
        *) return 1 ;;
    esac
}
