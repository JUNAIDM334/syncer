#!/bin/bash

# SSH Connection Management Module
# Provides SSH connection testing, password management, and command wrappers
# Note: utils.sh is already sourced by the main script

# Global variables for connection
USE_PASSWORD=0
SSH_PASSWORD=""

# SSH configuration variables - only set defaults if not already defined
: ${SSH_KEY_PATH:=""}
: ${SSH_OPTIONS:=""}
: ${SSH_PORT:="22"}

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

    # Debug: Show what SSH settings are available
    echo "DEBUG: SSH Configuration at test time:"
    echo "  SSH_KEY_PATH='$SSH_KEY_PATH'"
    echo "  SSH_OPTIONS='$SSH_OPTIONS'"
    echo "  SSH_PORT='$SSH_PORT'"

    # Build SSH command with custom options
    local ssh_test_cmd="ssh"
    local ssh_opts="-o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new"

    # Add port if specified
    if [ -n "$SSH_PORT" ] && [ "$SSH_PORT" != "22" ]; then
        ssh_opts="$ssh_opts -p $SSH_PORT"
    fi

    # Add custom SSH options
    if [ -n "$SSH_OPTIONS" ]; then
        ssh_opts="$ssh_opts $SSH_OPTIONS"
    fi

    # Don't add -i flag, let SSH use default keys or ssh_config
    # The IdentitiesOnly=yes option will handle key selection

    # Debug: Show final SSH command
    echo "DEBUG: Final SSH command: $ssh_test_cmd $ssh_opts -o BatchMode=yes $user@$host"

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
    local ssh_opts="-o StrictHostKeyChecking=accept-new"

    # Add port if specified
    if [ -n "$SSH_PORT" ] && [ "$SSH_PORT" != "22" ]; then
        ssh_opts="$ssh_opts -p $SSH_PORT"
    fi

    # Add custom SSH options
    if [ -n "$SSH_OPTIONS" ]; then
        ssh_opts="$ssh_opts $SSH_OPTIONS"
    fi

    # Don't add -i flag, let SSH use default keys or ssh_config
    # The IdentitiesOnly=yes option will handle key selection

    if [ "$USE_PASSWORD" -eq 1 ]; then
        sshpass -p "$SSH_PASSWORD" ssh $ssh_opts "$@"
    else
        ssh $ssh_opts "$@"
    fi
}

# Function to run rsync with or without password
rsync_cmd() {
    # Build SSH options for rsync
    local ssh_opts="ssh -o StrictHostKeyChecking=accept-new"

    # Add port if specified
    if [ -n "$SSH_PORT" ] && [ "$SSH_PORT" != "22" ]; then
        ssh_opts="$ssh_opts -p $SSH_PORT"
    fi

    # Add custom SSH options
    if [ -n "$SSH_OPTIONS" ]; then
        ssh_opts="$ssh_opts $SSH_OPTIONS"
    fi

    # Don't add -i flag, let SSH use default keys or ssh_config
    # The IdentitiesOnly=yes option will handle key selection

    if [ "$USE_PASSWORD" -eq 1 ]; then
        sshpass -p "$SSH_PASSWORD" rsync -e "$ssh_opts" "$@"
    else
        rsync -e "$ssh_opts" "$@"
    fi
}
