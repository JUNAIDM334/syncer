#!/bin/bash

# Whiptail/Dialog UI Module
# Menu-based interface with terminal fallback
# Used by: sync-laptop.sh

# Note: Colors are defined in utils.sh (already sourced)

# Check which dialog tool is available
# Can be overridden by setting NO_GUI=1 before sourcing this module
if [ "${NO_GUI:-0}" -eq 1 ]; then
    DIALOG="none"
elif command -v whiptail &> /dev/null; then
    DIALOG="whiptail"
elif command -v dialog &> /dev/null; then
    DIALOG="dialog"
else
    DIALOG="none"
fi

# Export for use in other functions
export DIALOG

# Show message box
show_msgbox() {
    local title="$1"
    local message="$2"

    if [ "$DIALOG" = "whiptail" ]; then
        whiptail --title "$title" --msgbox "$message" 20 70
    elif [ "$DIALOG" = "dialog" ]; then
        dialog --title "$title" --msgbox "$message" 20 70
        clear
    else
        echo ""
        echo "=========================================="
        echo "  $title"
        echo "=========================================="
        echo "$message"
        echo ""
        read -p "Press Enter to continue..."
    fi
}

# Ask yes/no question
ask_yes_no() {
    local prompt="$1"

    if [ "$DIALOG" = "whiptail" ]; then
        whiptail --title "Confirm" --yesno "$prompt" 10 60
        return $?
    elif [ "$DIALOG" = "dialog" ]; then
        dialog --title "Confirm" --yesno "$prompt" 10 60
        local result=$?
        clear
        return $result
    else
        local response
        while true; do
            read -p "$(echo -e ${BLUE}[?]${NC} $prompt [y/n]: )" response
            case "$response" in
                [Yy]* ) return 0;;
                [Nn]* ) return 1;;
                * ) echo "Please answer y or n.";;
            esac
        done
    fi
}

# Show menu
show_menu() {
    local title="$1"
    shift
    local options=("$@")

    if [ "$DIALOG" = "whiptail" ]; then
        whiptail --title "$title" --menu "Choose an option:" 25 80 15 "${options[@]}" 3>&1 1>&2 2>&3
    elif [ "$DIALOG" = "dialog" ]; then
        dialog --title "$title" --menu "Choose an option:" 25 80 15 "${options[@]}" 2>&1 >/dev/tty
        clear
    else
        # Fallback to simple menu
        echo ""
        echo "=========================================="
        echo "  $title"
        echo "=========================================="
        local i=0
        while [ $i -lt ${#options[@]} ]; do
            echo "${options[$i]}. ${options[$((i+1))]}"
            i=$((i+2))
        done
        echo ""
        read -p "Select option: " choice
        echo "$choice"
    fi
}

# Show checklist
show_checklist() {
    local title="$1"
    local prompt="$2"
    shift 2
    local options=("$@")

    if [ "$DIALOG" = "whiptail" ]; then
        whiptail --title "$title" --checklist "$prompt" 25 80 15 "${options[@]}" 3>&1 1>&2 2>&3
    elif [ "$DIALOG" = "dialog" ]; then
        dialog --title "$title" --checklist "$prompt" 25 80 15 "${options[@]}" 2>&1 >/dev/tty
        clear
    else
        # Fallback to simple selection
        echo ""
        echo "=========================================="
        echo "  $title"
        echo "=========================================="
        echo "$prompt"
        echo ""

        local i=0
        declare -a selected_items
        while [ $i -lt ${#options[@]} ]; do
            local key="${options[$i]}"
            local desc="${options[$((i+1))]}"
            local status="${options[$((i+2))]}"

            echo "$key. $desc"
            if ask_yes_no "Select '$desc'?"; then
                selected_items+=("\"$key\"")
            fi
            i=$((i+3))
        done

        echo "${selected_items[@]}"
    fi
}

# Show input box
show_inputbox() {
    local title="$1"
    local prompt="$2"
    local default="$3"

    if [ "$DIALOG" = "whiptail" ]; then
        whiptail --title "$title" --inputbox "$prompt" 10 60 "$default" 3>&1 1>&2 2>&3
    elif [ "$DIALOG" = "dialog" ]; then
        dialog --title "$title" --inputbox "$prompt" 10 60 "$default" 2>&1 >/dev/tty
        clear
    else
        # Fallback to simple input
        local value
        if [ -n "$default" ]; then
            read -p "$(echo -e ${BLUE}[?]${NC} $prompt [$default]: )" value
            echo "${value:-$default}"
        else
            read -p "$(echo -e ${BLUE}[?]${NC} $prompt: )" value
            echo "$value"
        fi
    fi
}

# Show message (alias for compatibility)
show_message() {
    show_msgbox "$@"
}

# Get input (alias for compatibility)
get_input() {
    local prompt="$1"
    local default="$2"
    show_inputbox "Input Required" "$prompt" "$default"
}
