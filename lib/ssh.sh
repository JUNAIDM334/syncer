#!/bin/bash

# SSH Connection Management Module
# Provides SSH connection testing, password management, and command wrappers
# Note: utils.sh is already sourced by the main script

# Global variables for connection
USE_PASSWORD=0
SSH_PASSWORD=""
SSH_KEY_PATH=""
SSH_OPTIONS=""
SSH_PORT="22"

# Function to check if rsync is installed
check_rsync() {
    if ! command -v rsync &> /dev/null; then
        print_error "rsync is not installed. Please install it first:"
        echo "  sudo apt install rsync"
        exit 1
    fi
}

# Function to check if sshpass is installed
check_sshpass() {
    if ! command -v sshpass &> /dev/null; then
        print_warning "sshpass is not installed. Installing it now for one-time password authentication..."
        if sudo apt update && sudo apt install -y sshpass; then
            print_success "sshpass installed successfully"
            return 0
        else
            print_error "Failed to install sshpass. You will need to enter password for each operation."
            if ask_yes_no "Continue without sshpass (you'll be prompted for password multiple times)?"; then
                return 1
            else
                print_error "Exiting script"
                exit 1
            fi
        fi
    else
        print_success "sshpass is already installed"
    fi
    return 0
}

# Function to test SSH connection
test_ssh_connection() {
    local user="$1"
    local host="$2"

    print_info "Testing SSH connection to $user@$host..."

    # Build SSH command with custom options
    local ssh_test_cmd="ssh"
    local ssh_opts="-o ConnectTimeout=5"

    # Add port if specified
    if [ -n "$SSH_PORT" ] && [ "$SSH_PORT" != "22" ]; then
        ssh_opts="$ssh_opts -p $SSH_PORT"
    fi

    # Add custom SSH options
    if [ -n "$SSH_OPTIONS" ]; then
        ssh_opts="$ssh_opts $SSH_OPTIONS"
    fi

    # Add identity file if specified
    if [ -n "$SSH_KEY_PATH" ]; then
        if [ -f "$SSH_KEY_PATH" ]; then
            ssh_opts="$ssh_opts -i $SSH_KEY_PATH"
            print_info "Using SSH key: $SSH_KEY_PATH"
        else
            print_warning "SSH key not found: $SSH_KEY_PATH (ignoring)"
        fi
    fi

    # First try without password (key-based auth)
    if $ssh_test_cmd $ssh_opts -o BatchMode=yes "$user@$host" "echo 'Connection successful'" &>/dev/null; then
        print_success "SSH key authentication successful"
        USE_PASSWORD=0
        return 0
    else
        print_warning "SSH key authentication not available"

        # Check if sshpass is available
        if command -v sshpass &> /dev/null; then
            print_info "Password will be requested once for all operations"
            read -sp "Enter SSH password for $user@$host: " SSH_PASSWORD
            echo ""

            # Test password (use same SSH options)
            if sshpass -p "$SSH_PASSWORD" $ssh_test_cmd $ssh_opts "$user@$host" "echo 'Connection successful'" &>/dev/null; then
                print_success "Password authentication successful"
                USE_PASSWORD=1
                export SSH_PASSWORD
                return 0
            else
                print_error "Password authentication failed"
                return 1
            fi
        else
            print_warning "You will need to enter password for each operation"
            print_info "Tip: Install sshpass or set up SSH key authentication"
            USE_PASSWORD=0
            return 1
        fi
    fi
}

# Function to run SSH command with or without password
ssh_cmd() {
    # Build SSH options string
    local ssh_opts=""

    # Add port if specified
    if [ -n "$SSH_PORT" ] && [ "$SSH_PORT" != "22" ]; then
        ssh_opts="$ssh_opts -p $SSH_PORT"
    fi

    # Add custom SSH options
    if [ -n "$SSH_OPTIONS" ]; then
        ssh_opts="$ssh_opts $SSH_OPTIONS"
    fi

    # Add identity file if specified
    if [ -n "$SSH_KEY_PATH" ] && [ -f "$SSH_KEY_PATH" ]; then
        ssh_opts="$ssh_opts -i $SSH_KEY_PATH"
    fi

    if [ "$USE_PASSWORD" -eq 1 ]; then
        sshpass -p "$SSH_PASSWORD" ssh $ssh_opts "$@"
    else
        ssh $ssh_opts "$@"
    fi
}

# Function to run rsync with or without password
rsync_cmd() {
    # Build SSH options for rsync
    local ssh_opts=""

    # Add port if specified
    if [ -n "$SSH_PORT" ] && [ "$SSH_PORT" != "22" ]; then
        ssh_opts="ssh -p $SSH_PORT"
    else
        ssh_opts="ssh"
    fi

    # Add custom SSH options
    if [ -n "$SSH_OPTIONS" ]; then
        ssh_opts="$ssh_opts $SSH_OPTIONS"
    fi

    # Add identity file if specified
    if [ -n "$SSH_KEY_PATH" ] && [ -f "$SSH_KEY_PATH" ]; then
        ssh_opts="$ssh_opts -i $SSH_KEY_PATH"
    fi

    if [ "$USE_PASSWORD" -eq 1 ]; then
        sshpass -p "$SSH_PASSWORD" rsync -e "$ssh_opts" "$@"
    else
        rsync -e "$ssh_opts" "$@"
    fi
}
