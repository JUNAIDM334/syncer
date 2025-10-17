#!/bin/bash

# Applications Discovery Module
# Discovers common applications (media, communication, graphics, office, etc.)
# Note: utils.sh and ssh.sh are sourced by the main script

# Check if application is installed locally
is_application_installed() {
    local app="$1"
    case "$app" in
        vlc) command -v vlc &>/dev/null ;;
        stremio) command -v stremio &>/dev/null || snap list 2>/dev/null | grep -q '^stremio ' ;;
        slack) command -v slack &>/dev/null || snap list 2>/dev/null | grep -q '^slack ' ;;
        discord) command -v discord &>/dev/null || snap list 2>/dev/null | grep -q '^discord ' ;;
        skype) command -v skypeforlinux &>/dev/null || snap list 2>/dev/null | grep -q '^skype ' ;;
        gimp) command -v gimp &>/dev/null ;;
        inkscape) command -v inkscape &>/dev/null ;;
        postman) snap list 2>/dev/null | grep -q '^postman ' ;;
        insomnia) snap list 2>/dev/null | grep -q '^insomnia ' ;;
        libreoffice) command -v libreoffice &>/dev/null ;;
        qbittorrent) command -v qbittorrent &>/dev/null ;;
        transmission) command -v transmission-gtk &>/dev/null ;;
        *) return 1 ;;
    esac
}

# Discover applications on source laptop
discover_applications() {
    local source_user="$1"
    local source_host="$2"
    local source_home="$3"

    print_info "Detecting applications..."

    # Initialize global OTHER_APPS array if not already declared
    declare -gA OTHER_APPS

    # Media Players
    if ssh_cmd "$source_user@$source_host" "command -v vlc &>/dev/null" 2>/dev/null; then
        OTHER_APPS["vlc"]="installed|native"
        echo "  ✓ VLC Media Player"
    fi

    if ssh_cmd "$source_user@$source_host" "snap list 2>/dev/null | grep -q '^stremio '" 2>/dev/null; then
        OTHER_APPS["stremio"]="installed|snap"
        echo "  ✓ Stremio (snap)"
    elif ssh_cmd "$source_user@$source_host" "command -v stremio &>/dev/null" 2>/dev/null; then
        OTHER_APPS["stremio"]="installed|native"
        echo "  ✓ Stremio (native)"
    fi

    # Communication Apps
    if ssh_cmd "$source_user@$source_host" "snap list 2>/dev/null | grep -q '^slack '" 2>/dev/null; then
        OTHER_APPS["slack"]="installed|snap"
        echo "  ✓ Slack (snap)"
    elif ssh_cmd "$source_user@$source_host" "command -v slack &>/dev/null" 2>/dev/null; then
        OTHER_APPS["slack"]="installed|native"
        echo "  ✓ Slack (native)"
    fi

    if ssh_cmd "$source_user@$source_host" "snap list 2>/dev/null | grep -q '^discord '" 2>/dev/null; then
        OTHER_APPS["discord"]="installed|snap"
        echo "  ✓ Discord (snap)"
    elif ssh_cmd "$source_user@$source_host" "command -v discord &>/dev/null" 2>/dev/null; then
        OTHER_APPS["discord"]="installed|native"
        echo "  ✓ Discord (native)"
    fi

    if ssh_cmd "$source_user@$source_host" "snap list 2>/dev/null | grep -q '^skype '" 2>/dev/null; then
        OTHER_APPS["skype"]="installed|snap"
        echo "  ✓ Skype (snap)"
    elif ssh_cmd "$source_user@$source_host" "command -v skypeforlinux &>/dev/null" 2>/dev/null; then
        OTHER_APPS["skype"]="installed|native"
        echo "  ✓ Skype (native)"
    fi

    # Graphics Applications
    if ssh_cmd "$source_user@$source_host" "command -v gimp &>/dev/null" 2>/dev/null; then
        OTHER_APPS["gimp"]="installed|native"
        echo "  ✓ GIMP"
    fi

    if ssh_cmd "$source_user@$source_host" "command -v inkscape &>/dev/null" 2>/dev/null; then
        OTHER_APPS["inkscape"]="installed|native"
        echo "  ✓ Inkscape"
    fi

    # API Testing Tools
    if ssh_cmd "$source_user@$source_host" "snap list 2>/dev/null | grep -q '^postman '" 2>/dev/null; then
        OTHER_APPS["postman"]="installed|snap"
        echo "  ✓ Postman (snap)"
    fi

    if ssh_cmd "$source_user@$source_host" "snap list 2>/dev/null | grep -q '^insomnia '" 2>/dev/null; then
        OTHER_APPS["insomnia"]="installed|snap"
        echo "  ✓ Insomnia (snap)"
    fi

    # Office Suite
    if ssh_cmd "$source_user@$source_host" "command -v libreoffice &>/dev/null" 2>/dev/null; then
        OTHER_APPS["libreoffice"]="installed|native"
        echo "  ✓ LibreOffice"
    fi

    # Torrent Clients
    if ssh_cmd "$source_user@$source_host" "command -v qbittorrent &>/dev/null" 2>/dev/null; then
        OTHER_APPS["qbittorrent"]="installed|native"
        echo "  ✓ qBittorrent"
    fi

    if ssh_cmd "$source_user@$source_host" "command -v transmission-gtk &>/dev/null" 2>/dev/null; then
        OTHER_APPS["transmission"]="installed|native"
        echo "  ✓ Transmission"
    fi

    if [ ${#OTHER_APPS[@]} -eq 0 ]; then
        echo "  No additional applications detected"
    fi
}
