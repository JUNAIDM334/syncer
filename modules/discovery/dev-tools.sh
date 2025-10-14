#!/bin/bash

# Development Tools Discovery Module
# Detects installed development tools, IDEs, and their configurations
# Note: utils.sh and ssh.sh are sourced by the main script

# Discover development tools on remote host
discover_dev_tools() {
    local source_user="$1"
    local source_host="$2"
    local source_home="$3"

    declare -gA DEV_TOOLS

    print_info "Detecting development tools..."

    # VSCode
    if ssh_cmd "$source_user@$source_host" "command -v code &>/dev/null" 2>/dev/null; then
        DEV_TOOLS["vscode"]="installed|IDE"
        echo "  ✓ VSCode"
        if ssh_cmd "$source_user@$source_host" "test -d $source_home/.config/Code" 2>/dev/null; then
            DEV_TOOLS["vscode-config"]="config|$source_home/.config/Code/"
        fi
    fi

    # Docker
    if ssh_cmd "$source_user@$source_host" "command -v docker &>/dev/null" 2>/dev/null; then
        DOCKER_VERSION=$(ssh_cmd "$source_user@$source_host" "docker --version 2>/dev/null | awk '{print \$3}' | cut -d, -f1" 2>/dev/null)
        DEV_TOOLS["docker"]="installed|$DOCKER_VERSION"
        echo "  ✓ Docker ($DOCKER_VERSION)"
        if ssh_cmd "$source_user@$source_host" "test -d $source_home/.docker" 2>/dev/null; then
            DEV_TOOLS["docker-config"]="config|$source_home/.docker/"
        fi
    fi

    # Node.js
    if ssh_cmd "$source_user@$source_host" "command -v node &>/dev/null" 2>/dev/null; then
        NODE_VERSION=$(ssh_cmd "$source_user@$source_host" "node --version 2>/dev/null" 2>/dev/null)
        DEV_TOOLS["nodejs"]="installed|$NODE_VERSION"
        echo "  ✓ Node.js ($NODE_VERSION)"
        if ssh_cmd "$source_user@$source_host" "test -f $source_home/.npmrc" 2>/dev/null; then
            DEV_TOOLS["npm-config"]="config|$source_home/.npmrc"
        fi
    fi

    # Python
    if ssh_cmd "$source_user@$source_host" "command -v python3 &>/dev/null" 2>/dev/null; then
        PYTHON_VERSION=$(ssh_cmd "$source_user@$source_host" "python3 --version 2>/dev/null | awk '{print \$2}'" 2>/dev/null)
        DEV_TOOLS["python3"]="installed|$PYTHON_VERSION"
        echo "  ✓ Python ($PYTHON_VERSION)"
    fi

    # Git
    if ssh_cmd "$source_user@$source_host" "command -v git &>/dev/null" 2>/dev/null; then
        GIT_VERSION=$(ssh_cmd "$source_user@$source_host" "git --version 2>/dev/null | awk '{print \$3}'" 2>/dev/null)
        DEV_TOOLS["git"]="installed|$GIT_VERSION"
        echo "  ✓ Git ($GIT_VERSION)"
    fi

    # Ruby
    if ssh_cmd "$source_user@$source_host" "command -v ruby &>/dev/null" 2>/dev/null; then
        RUBY_VERSION=$(ssh_cmd "$source_user@$source_host" "ruby --version 2>/dev/null | awk '{print \$2}'" 2>/dev/null)
        DEV_TOOLS["ruby"]="installed|$RUBY_VERSION"
        echo "  ✓ Ruby ($RUBY_VERSION)"
    fi

    # Go
    if ssh_cmd "$source_user@$source_host" "command -v go &>/dev/null" 2>/dev/null; then
        GO_VERSION=$(ssh_cmd "$source_user@$source_host" "go version 2>/dev/null | awk '{print \$3}'" 2>/dev/null)
        DEV_TOOLS["golang"]="installed|$GO_VERSION"
        echo "  ✓ Go ($GO_VERSION)"
    fi

    # Rust
    if ssh_cmd "$source_user@$source_host" "command -v rustc &>/dev/null" 2>/dev/null; then
        RUST_VERSION=$(ssh_cmd "$source_user@$source_host" "rustc --version 2>/dev/null | awk '{print \$2}'" 2>/dev/null)
        DEV_TOOLS["rust"]="installed|$RUST_VERSION"
        echo "  ✓ Rust ($RUST_VERSION)"
        if ssh_cmd "$source_user@$source_host" "test -d $source_home/.cargo" 2>/dev/null; then
            DEV_TOOLS["cargo-config"]="config|$source_home/.cargo/"
        fi
    fi

    # JetBrains IDEs
    for ide in pycharm phpstorm webstorm idea goland rubymine; do
        if ssh_cmd "$source_user@$source_host" "command -v $ide &>/dev/null" 2>/dev/null; then
            DEV_TOOLS["$ide"]="installed|IDE"
            echo "  ✓ $ide"
        fi
    done
}

# Check if dev tool is installed locally
is_devtool_installed() {
    local tool="$1"
    case "$tool" in
        vscode) command -v code &>/dev/null ;;
        docker) command -v docker &>/dev/null ;;
        nodejs) command -v node &>/dev/null ;;
        python3) command -v python3 &>/dev/null ;;
        ruby) command -v ruby &>/dev/null ;;
        golang) command -v go &>/dev/null ;;
        rust) command -v rustc &>/dev/null ;;
        git) command -v git &>/dev/null ;;
        pycharm|phpstorm|webstorm|idea|goland|rubymine) command -v $tool &>/dev/null ;;
        *) return 1 ;;
    esac
}
