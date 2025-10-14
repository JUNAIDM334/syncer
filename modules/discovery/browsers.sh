#!/bin/bash

# Browser Discovery Module
# Detects installed browsers and their profile locations
# Note: utils.sh and ssh.sh are sourced by the main script

# Discover browsers on remote host
discover_browsers() {
    local source_user="$1"
    local source_host="$2"
    local source_home="$3"

    declare -gA BROWSERS

    print_info "Detecting browsers..."

    # Firefox - verify profile data exists
    if ssh_cmd "$source_user@$source_host" "command -v firefox &>/dev/null" 2>/dev/null; then
        FIREFOX_TYPE=$(ssh_cmd "$source_user@$source_host" "snap list 2>/dev/null | grep -q firefox && echo 'snap' || echo 'native'" 2>/dev/null)
        if [ "$FIREFOX_TYPE" = "snap" ]; then
            if ssh_cmd "$source_user@$source_host" "test -d $source_home/snap/firefox/common/.mozilla/firefox" 2>/dev/null; then
                BROWSERS["firefox"]="snap|$source_home/snap/firefox/common/.mozilla/firefox/"
                echo "  ✓ Firefox (snap)"
            else
                echo "  ⚠ Firefox (snap) installed but no profile data found"
            fi
        else
            if ssh_cmd "$source_user@$source_host" "test -d $source_home/.mozilla/firefox" 2>/dev/null; then
                BROWSERS["firefox"]="native|$source_home/.mozilla/firefox/"
                echo "  ✓ Firefox (native)"
            else
                echo "  ⚠ Firefox (native) installed but no profile data found"
            fi
        fi
    fi

    # Chrome - verify profile data exists
    if ssh_cmd "$source_user@$source_host" "command -v google-chrome &>/dev/null || command -v google-chrome-stable &>/dev/null" 2>/dev/null; then
        if ssh_cmd "$source_user@$source_host" "test -d $source_home/.config/google-chrome" 2>/dev/null; then
            BROWSERS["google-chrome"]="native|$source_home/.config/google-chrome/"
            echo "  ✓ Google Chrome"
        else
            echo "  ⚠ Google Chrome installed but no profile data found"
        fi
    fi

    # Chromium - find actual profile path
    local chromium_type=""
    local chromium_path=""
    local chromium_found=0

    # Check if snap chromium is installed
    if ssh_cmd "$source_user@$source_host" "snap list chromium 2>/dev/null | grep -q '^chromium'" 2>/dev/null; then
        local snap_paths=(
            "$source_home/snap/chromium/common/.config/chromium"
            "$source_home/snap/chromium/current/.config/chromium"
            "$source_home/snap/chromium/.config/chromium"
        )

        for path in "${snap_paths[@]}"; do
            if ssh_cmd "$source_user@$source_host" "test -d $path" 2>/dev/null; then
                chromium_type="snap"
                chromium_path="$path/"
                chromium_found=1
                echo "  ✓ Chromium (snap) - Path: $path"
                break
            fi
        done

        if [ $chromium_found -eq 0 ]; then
            local found_path=$(ssh_cmd "$source_user@$source_host" "find $source_home/snap/chromium -type d -name 'chromium' -path '*/.config/chromium' 2>/dev/null | head -1" 2>/dev/null)
            if [ -n "$found_path" ]; then
                chromium_type="snap"
                chromium_path="$found_path/"
                chromium_found=1
                echo "  ✓ Chromium (snap) - Found at: $found_path"
            fi
        fi
    fi

    # Check for native chromium if snap not found
    if [ $chromium_found -eq 0 ]; then
        if ssh_cmd "$source_user@$source_host" "command -v chromium-browser &>/dev/null || command -v chromium &>/dev/null" 2>/dev/null; then
            if ssh_cmd "$source_user@$source_host" "test -d $source_home/.config/chromium" 2>/dev/null; then
                chromium_type="native"
                chromium_path="$source_home/.config/chromium/"
                chromium_found=1
                echo "  ✓ Chromium (native)"
            fi
        fi
    fi

    # Add to BROWSERS if found
    if [ $chromium_found -eq 1 ]; then
        BROWSERS["chromium"]="$chromium_type|$chromium_path"
    fi

    # Brave
    if ssh_cmd "$source_user@$source_host" "command -v brave-browser &>/dev/null" 2>/dev/null; then
        if ssh_cmd "$source_user@$source_host" "test -d $source_home/.config/BraveSoftware" 2>/dev/null; then
            BROWSERS["brave"]="native|$source_home/.config/BraveSoftware/"
            echo "  ✓ Brave Browser"
        fi
    fi
}

# Check if browser is installed locally
is_browser_installed() {
    local browser="$1"
    case "$browser" in
        firefox) command -v firefox &>/dev/null ;;
        google-chrome) command -v google-chrome &>/dev/null || command -v google-chrome-stable &>/dev/null ;;
        chromium) command -v chromium &>/dev/null || command -v chromium-browser &>/dev/null ;;
        brave) command -v brave-browser &>/dev/null ;;
        *) return 1 ;;
    esac
}
