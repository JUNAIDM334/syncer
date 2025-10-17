#!/bin/bash

# Terminal-Only UI Module
# Simple prompts without whiptail/dialog
# Used by: sync-laptop-modular.sh

# Note: Colors are defined in utils.sh (already sourced)

# Ask yes/no question (terminal only)
ask_yes_no() {
    local prompt="$1"
    local response
    while true; do
        read -p "$(echo -e ${BLUE}[?]${NC} $prompt [y/n]: )" response
        case "$response" in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer y or n.";;
        esac
    done
}

# Show message (terminal only)
show_message() {
    local title="$1"
    local message="$2"
    echo ""
    echo "=========================================="
    echo "  $title"
    echo "=========================================="
    echo "$message"
    echo ""
    read -p "Press Enter to continue..."
}

# Get input from user
get_input() {
    local prompt="$1"
    local default="$2"
    local value

    if [ -n "$default" ]; then
        read -p "$(echo -e ${BLUE}[?]${NC} $prompt [$default]: )" value
        echo "${value:-$default}"
    else
        read -p "$(echo -e ${BLUE}[?]${NC} $prompt: )" value
        echo "$value"
    fi
}
