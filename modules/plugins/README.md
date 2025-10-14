# Plugin System

This directory contains custom plugins for extending the sync script functionality.

## Creating a Plugin

Create a new `.sh` file in this directory with the following structure:

```bash
#!/bin/bash

# Plugin Name: My Custom Plugin
# Description: Syncs custom application data

# Source required modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../../lib" && pwd)"
source "$LIB_DIR/utils.sh"
source "$LIB_DIR/ssh.sh"

# Plugin discovery function
plugin_discover() {
    local source_user="$1"
    local source_host="$2"
    local source_home="$3"

    print_info "Running custom plugin discovery..."

    # Add your discovery logic here
    # Return 0 if something was found, 1 otherwise
    return 0
}

# Plugin sync function
plugin_sync() {
    local source_user="$1"
    local source_host="$2"
    local source_home="$3"
    local dest_home="$4"

    print_info "Running custom plugin sync..."

    # Add your sync logic here
    return 0
}

# Export functions
export -f plugin_discover
export -f plugin_sync
```

## Using Plugins

Plugins are automatically loaded by the main script if placed in this directory.
Name your plugin file descriptively, e.g., `custom-app-sync.sh`

## Example Use Cases

- Sync custom application configurations
- Sync game saves
- Sync IDE-specific settings
- Sync cloud storage configurations
- Sync custom development environments
