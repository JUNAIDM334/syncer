#!/bin/bash

# Application Installer Module
# Provides installation functionality for various applications
# Note: utils.sh is sourced by the main script
# Note: app-registry.sh is sourced by the main script before this module

# Install application with error handling
install_application() {
    local app="$1"
    local type="${2:-native}"  # Default to native if not specified
    local install_status=0

    print_info "Installing: $app ($type)"

    # Get installation command from registry
    local install_cmd=$(get_install_command "$app" "$type")

    if [ -z "$install_cmd" ]; then
        print_error "No installation method found for: $app"
        return 1
    fi

    # Execute installation
    eval "$install_cmd"
    install_status=$?

    # Verify installation
    if [ $install_status -eq 0 ]; then
        if verify_installation "$app"; then
            print_success "Successfully installed and verified: $app"
            return 0
        else
            print_warning "Installation completed but verification failed for: $app"
            print_info "The app may need a system restart or manual verification"
            return 0
        fi
    else
        print_error "Failed to install: $app (exit code: $install_status)"
        return 1
    fi
}

# Verify if application is installed
verify_installation() {
    local app="$1"

    case "$app" in
        firefox) command -v firefox &>/dev/null ;;
        google-chrome) command -v google-chrome &>/dev/null || command -v google-chrome-stable &>/dev/null ;;
        chromium) command -v chromium &>/dev/null || command -v chromium-browser &>/dev/null || snap list 2>/dev/null | grep -q '^chromium ' ;;
        brave) command -v brave-browser &>/dev/null ;;
        postgresql) command -v psql &>/dev/null ;;
        mysql) command -v mysql &>/dev/null ;;
        mongodb) command -v mongosh &>/dev/null || command -v mongo &>/dev/null ;;
        redis) command -v redis-cli &>/dev/null ;;
        dbeaver) command -v dbeaver &>/dev/null ;;
        vscode) command -v code &>/dev/null ;;
        docker) command -v docker &>/dev/null ;;
        nodejs) command -v node &>/dev/null ;;
        python3) command -v python3 &>/dev/null ;;
        git) command -v git &>/dev/null ;;
        ruby) command -v ruby &>/dev/null ;;
        golang) command -v go &>/dev/null ;;
        rust) command -v rustc &>/dev/null ;;
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
        *)
            print_warning "No verification method for: $app"
            return 1
            ;;
    esac
}
