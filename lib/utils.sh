#!/bin/bash

# Core Utilities Module
# Provides color definitions, logging functions, and basic utilities

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Note: UI functions (ask_yes_no, show_message, etc.) have been moved to:
# - lib/ui-base.sh (terminal-only, for sync-laptop-modular.sh)
# - lib/ui-menu.sh (whiptail/dialog support, for sync-laptop.sh)
