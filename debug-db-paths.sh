#!/bin/bash

# Debug script to show database paths on source laptop
# Run this on the SOURCE laptop to find database directories

echo "=========================================="
echo "  Database Directory Detective"
echo "=========================================="
echo ""

# Check PostgreSQL
echo "=== PostgreSQL ==="
if command -v psql &>/dev/null; then
    echo "✓ PostgreSQL is installed"
    psql --version
    echo ""
    echo "Service status:"
    systemctl status postgresql 2>/dev/null | grep Active || echo "  Not running via systemd"
    echo ""
    echo "Checking possible data directories:"
    for dir in /var/lib/postgresql /var/lib/pgsql /var/snap/postgresql/common; do
        if [ -d "$dir" ]; then
            echo "  ✓ $dir exists"
            sudo ls -la "$dir" 2>/dev/null | head -5
            echo "    Files: $(sudo find "$dir" -type f 2>/dev/null | wc -l)"
        else
            echo "  ✗ $dir does not exist"
        fi
    done

    # Try to find actual data directory from config
    DATA_DIR=$(sudo -u postgres psql -t -P format=unaligned -c 'SHOW data_directory;' 2>/dev/null)
    if [ -n "$DATA_DIR" ]; then
        echo ""
        echo "  Actual data directory (from PostgreSQL): $DATA_DIR"
    fi
else
    echo "✗ PostgreSQL not installed"
fi

echo ""
echo "=== MySQL/MariaDB ==="
if command -v mysql &>/dev/null; then
    echo "✓ MySQL is installed"
    mysql --version
    echo ""
    echo "Service status:"
    systemctl status mysql 2>/dev/null | grep Active || echo "  Not running via systemd"
    echo ""
    echo "Checking possible data directories:"
    for dir in /var/lib/mysql /var/lib/mysql-files /var/snap/mysql/common/data; do
        if [ -d "$dir" ]; then
            echo "  ✓ $dir exists"
            sudo ls -la "$dir" 2>/dev/null | head -5
            echo "    Files: $(sudo find "$dir" -type f 2>/dev/null | wc -l)"
        else
            echo "  ✗ $dir does not exist"
        fi
    done

    # Try to find actual data directory from config
    DATA_DIR=$(sudo mysql -NBe "SELECT @@datadir;" 2>/dev/null)
    if [ -n "$DATA_DIR" ]; then
        echo ""
        echo "  Actual data directory (from MySQL): $DATA_DIR"
    fi
else
    echo "✗ MySQL not installed"
fi

echo ""
echo "=== MongoDB ==="
if command -v mongod &>/dev/null || command -v mongosh &>/dev/null; then
    echo "✓ MongoDB is installed"
    mongod --version 2>/dev/null | head -1 || mongosh --version
    echo ""
    echo "Service status:"
    systemctl status mongod 2>/dev/null | grep Active || echo "  Not running via systemd"
    echo ""
    echo "Checking possible data directories:"
    for dir in /var/lib/mongodb /var/lib/mongo /var/snap/mongodb/common; do
        if [ -d "$dir" ]; then
            echo "  ✓ $dir exists"
            sudo ls -la "$dir" 2>/dev/null | head -5
            echo "    Files: $(sudo find "$dir" -type f 2>/dev/null | wc -l)"
        else
            echo "  ✗ $dir does not exist"
        fi
    done
else
    echo "✗ MongoDB not installed"
fi

echo ""
echo "=== Redis ==="
if command -v redis-server &>/dev/null || command -v redis-cli &>/dev/null; then
    echo "✓ Redis is installed"
    redis-server --version 2>/dev/null || redis-cli --version
    echo ""
    echo "Service status:"
    systemctl status redis-server 2>/dev/null | grep Active || systemctl status redis 2>/dev/null | grep Active || echo "  Not running via systemd"
    echo ""
    echo "Checking possible data directories:"
    for dir in /var/lib/redis /var/snap/redis/common; do
        if [ -d "$dir" ]; then
            echo "  ✓ $dir exists"
            sudo ls -la "$dir" 2>/dev/null | head -5
            echo "    Files: $(sudo find "$dir" -type f 2>/dev/null | wc -l)"
        else
            echo "  ✗ $dir does not exist"
        fi
    done
else
    echo "✗ Redis not installed"
fi

echo ""
echo "=========================================="
echo "Copy the paths shown above to use in sync"
echo "=========================================="
