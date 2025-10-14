# Ubuntu Laptop Sync Script

An intelligent automated script to sync data and applications between two Ubuntu laptops using rsync over SSH.

## Features

### 🔍 Smart Detection
- **Auto-discovers** installed applications on source laptop
- **Detects browsers**: Firefox, Chrome, Chromium, Brave (both snap and native)
- **Detects database clients**: PostgreSQL, MySQL, MongoDB, Redis, DBeaver
- **Detects development tools**: VSCode, Docker, Node.js, Python, Ruby, Go, Rust, Git, JetBrains IDEs
- **Finds correct data paths** (e.g., `~/snap/firefox/common/.mozilla/firefox/` for snap Firefox)

### 📦 Application Installation
- Checks if applications exist on new laptop
- Offers to install missing applications automatically
- Installs correct version type (snap vs native package)

### 🔄 Data Synchronization
- **Configuration files**: SSH keys, Git config, bash aliases, AWS config
- **Browser data**: Complete profiles with bookmarks, extensions, passwords
- **Database configs**: Connection strings, saved queries, credentials
- **Database backups**: Automatic dump, transfer, and restore of actual databases
- **Development tool settings**: VSCode extensions, Docker config, npm settings
- **User directories**: Documents, Downloads, Desktop, Pictures, Videos, Music
- **Custom directories**: Add any additional folders to sync

### 🎯 Interactive Selection
- Organized prompts by category
- Only shows items that exist on source laptop
- Clear descriptions of what will be synced
- Summary before proceeding

## Prerequisites

1. **Both laptops must be on the same network**
2. **SSH access** to the old laptop
3. **rsync installed** (script checks automatically)
4. **sshpass** (optional, for password automation)

```bash
# Install required tools
sudo apt install rsync

# Install sshpass for password automation (optional but recommended)
sudo apt install sshpass
```

**Note:** The script will offer to install `sshpass` if not found. With `sshpass`, you only enter the SSH password **once** at the beginning, and it's reused for all operations.

## Usage

### 1. Run the script on your new laptop

```bash
./sync-laptop.sh
```

### 2. Provide source laptop details

```
Source username:
Source IP address:
Source home directory [/home/user]: (press Enter)
```

### 3. The script will:
- Test SSH connection
- Discover all installed applications and folders
- Display what was found:
  ```
  === Browsers Detected ===
    - firefox (snap): ~/snap/firefox/common/.mozilla/firefox/
    - google-chrome (native): ~/.config/google-chrome/

  === Database Clients Detected ===
    - postgresql (version: 14.5)
    - mysql (version: 8.0.32)
    - dbeaver (version: gui)

  === Development Tools Detected ===
    - vscode (IDE)
    - docker (20.10.21)
    - nodejs (v18.12.0)
  ```

### 4. Interactive selection
The script will ask about each item found:
- Configuration files (SSH, Git, bash, etc.)
- Browser data and installation
- Database clients installation
- **Database backup selection** (lists all databases, choose which to backup)
- Development tools and settings
- User directories
- Custom directories

**Database Backup Example:**
```
Found: postgresql (version: 14.5)
Backup and transfer PostgreSQL databases? [y/n]: y

Listing databases on source laptop...
PostgreSQL databases found:
  - myapp_db
  - test_db
  - production_db

Backup all PostgreSQL databases? [y/n]: n
Backup database 'myapp_db'? [y/n]: y
Backup database 'test_db'? [y/n]: n
Backup database 'production_db'? [y/n]: y
```

### 5. Review and proceed
```
========================================
  Summary
========================================

Applications to install:
  - firefox
  - postgresql
  - vscode

Databases to backup and transfer:
  - postgresql: myapp_db
  - postgresql: production_db

Configuration/Data items to sync:
  - SSH configuration
  - Git configuration
  - firefox profile (snap)
  - PostgreSQL configuration
  - VSCode configuration
  - Documents

Proceed with installation and sync? [y/n]:
```

### 6. Installation, backup, and sync
The script executes in this order:

1. **Install applications** (if any selected)
2. **Create database backups** on source laptop
   - `pg_dumpall` for PostgreSQL
   - `mysqldump` for MySQL
   - `mongodump` for MongoDB
3. **Transfer backups** to new laptop (`~/db_backups/`)
4. **Optionally restore databases** immediately
5. **Sync configuration files** with progress display
6. **Fix SSH permissions** automatically

**Database Restore:**
```
Restore databases now? [y/n]: y

[INFO] Restoring PostgreSQL database: myapp_db
[SUCCESS] Database restored: myapp_db

[INFO] Restoring PostgreSQL database: production_db
[SUCCESS] Database restored: production_db
```

If you choose not to restore now, backups are saved in `~/db_backups/` for manual restoration later.

## Correct Browser Data Paths

The script uses the correct paths for browser data:

| Browser | Type | Source Path | Destination Path |
|---------|------|-------------|------------------|
| Firefox | Snap | `~/snap/firefox/common/.mozilla/firefox/` | `~/snap/firefox/common/.mozilla/firefox/` |
| Firefox | Native | `~/.mozilla/firefox/` | `~/.mozilla/firefox/` |
| Chrome | Native | `~/.config/google-chrome/` | `~/.config/google-chrome/` |
| Chromium | Snap | `~/snap/chromium/common/.config/chromium/` | `~/snap/chromium/common/.config/chromium/` |
| Chromium | Native | `~/.config/chromium/` | `~/.config/chromium/` |
| Brave | Native | `~/.config/BraveSoftware/` | `~/.config/BraveSoftware/` |

## Database Backup & Restore

### Automatic Database Migration

The script can automatically backup, transfer, and restore your databases:

#### Supported Databases
- **PostgreSQL**: Uses `pg_dump` / `pg_dumpall`
- **MySQL/MariaDB**: Uses `mysqldump`
- **MongoDB**: Uses `mongodump` / `mongorestore`

#### Process
1. Lists all databases on source laptop
2. Let you choose which to backup (or all)
3. Creates SQL dumps on source laptop
4. Transfers to `~/db_backups/` on new laptop
5. Optionally restores immediately

#### Manual Restore Commands

If you skip automatic restore, use these commands:

**PostgreSQL:**
```bash
# Restore all databases
psql -U postgres -f ~/db_backups/postgresql_all.sql

# Restore specific database
createdb myapp_db
psql -U postgres myapp_db -f ~/db_backups/postgresql_myapp_db.sql
```

**MySQL:**
```bash
# Restore all databases
mysql < ~/db_backups/mysql_all.sql

# Restore specific database
mysql myapp_db < ~/db_backups/mysql_myapp_db.sql
```

**MongoDB:**
```bash
# Restore all databases
mongorestore ~/db_backups/mongodb_backup

# Restore specific database
mongorestore ~/db_backups/mongodb_myapp_db
```

### Database Config Files

Configuration files are synced separately:

| Database | Config Files | Path |
|----------|-------------|------|
| PostgreSQL | .pgpass, .psqlrc | `~/.pgpass`, `~/.psqlrc` |
| MySQL | .my.cnf | `~/.my.cnf` |
| MongoDB | .mongorc.js | `~/.mongorc.js` |
| DBeaver | Connection data | `~/.local/share/DBeaverData/` |

## Password Options

### Option 1: One-Time Password Entry (Recommended for Quick Setup)

The script uses `sshpass` to ask for your SSH password **once** at the beginning, then reuses it for all operations.

```bash
./sync-laptop.sh
# Enter password once when prompted
# Password is used automatically for all subsequent operations
```

### Option 2: SSH Key Authentication (Recommended for Regular Use)

For completely passwordless operation, set up SSH key authentication:

```bash
# On new laptop
ssh-keygen -t ed25519 -C "your_email@example.com"
ssh-copy-id username@source-laptop-ip

# Test
ssh username@source-laptop-ip
# Should connect without password
```

**Benefits:**
- No password entry needed at all
- More secure than password authentication
- Works even without `sshpass`

## What Gets Synced

### Configuration Files
- `~/.ssh` - SSH keys and config
- `~/.gitconfig` - Git settings
- `~/.bash_aliases` - Custom aliases
- `~/.bashrc` - Bash configuration
- `~/.aws` - AWS credentials
- `~/.docker` - Docker config
- `~/.npmrc` - npm settings
- `~/.cargo` - Rust/Cargo config

### Application Data
- Browser profiles (bookmarks, extensions, passwords)
- Database client configurations
- IDE settings and extensions
- Docker containers and images config

### User Files
- Documents, Downloads, Desktop
- Pictures, Videos, Music
- Custom work directories (workspace, projects, dev)

## Behavior

- **Overwrites**: Existing files are replaced if source is newer/different
- **Adds**: New files from source are added
- **Keeps**: Files only on destination are kept
- **SSH permissions**: Automatically fixed after sync

## Troubleshooting

### Connection Issues
```bash
# Test SSH connection manually
ssh username@source-ip

# Check if rsync is installed on both laptops
rsync --version
```

### Permission Denied
```bash
# Make script executable
chmod +x sync-laptop.sh

# For SSH issues, set up key-based authentication
ssh-copy-id username@source-ip
```

### Slow Sync
- Use wired connection if possible
- Large browser profiles can take time
- Consider excluding cache folders if needed

## Notes

- Script requires sudo for installing applications
- Browser data includes passwords (ensure secure connection)
- Database configs may contain credentials
- First run may take time depending on data size
- Restart shell after sync: `source ~/.bashrc`

## Safety

- Script only syncs, never deletes files from destination
- Shows summary before proceeding
- Can be cancelled at any time with Ctrl+C
- SSH permissions are automatically secured
- Does not sync system files, only user data

## Examples

### Sync everything from old laptop
```bash
./sync-laptop.sh
# Answer 'y' to all prompts
```

### Sync only configurations
```bash
./sync-laptop.sh
# Answer 'y' only to configuration prompts
# Answer 'n' to user directories
```

### Custom directory sync
```bash
./sync-laptop.sh
# Navigate to "Add custom directory"
# Enter paths when prompted
```
