#!/bin/bash

# Application Registry
# Central registry of installation commands for all supported applications

# Get installation command for an application
get_install_command() {
    local app="$1"
    local type="${2:-native}"

    case "$app" in
        # Browsers
        firefox)
            if [ "$type" = "snap" ]; then
                echo "sudo snap install firefox"
            else
                echo "sudo apt update && sudo apt install -y firefox"
            fi
            ;;
        google-chrome)
            echo "wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo apt-key add - && \
                  echo 'deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main' | sudo tee /etc/apt/sources.list.d/google-chrome.list && \
                  sudo apt update && sudo apt install -y google-chrome-stable"
            ;;
        chromium)
            if [ "$type" = "snap" ]; then
                echo "sudo snap install chromium"
            else
                echo "sudo apt update && sudo apt install -y chromium-browser"
            fi
            ;;
        brave)
            echo "sudo apt install -y curl && \
                  curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg && \
                  echo 'deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main' | sudo tee /etc/apt/sources.list.d/brave-browser-release.list && \
                  sudo apt update && sudo apt install -y brave-browser"
            ;;

        # Database Clients & Servers
        postgresql)
            echo "sudo apt update && sudo apt install -y postgresql postgresql-contrib"
            ;;
        mysql)
            echo "sudo apt update && sudo apt install -y mysql-server"
            ;;
        mongodb)
            echo "sudo apt update && (sudo apt install -y mongodb-org || sudo apt install -y mongodb)"
            ;;
        redis)
            echo "sudo apt update && sudo apt install -y redis-server"
            ;;
        dbeaver)
            echo "wget -O /tmp/dbeaver.deb https://dbeaver.io/files/dbeaver-ce_latest_amd64.deb && \
                  sudo dpkg -i /tmp/dbeaver.deb || sudo apt-get install -f -y && \
                  rm -f /tmp/dbeaver.deb"
            ;;

        # Development Tools
        vscode)
            echo "wget -q -O - https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add - && \
                  echo 'deb [arch=amd64] https://packages.microsoft.com/repos/vscode stable main' | sudo tee /etc/apt/sources.list.d/vscode.list && \
                  sudo apt update && sudo apt install -y code"
            ;;
        docker)
            echo "sudo apt update && \
                  sudo apt install -y ca-certificates curl gnupg && \
                  sudo install -m 0755 -d /etc/apt/keyrings && \
                  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null && \
                  sudo chmod a+r /etc/apt/keyrings/docker.gpg && \
                  echo 'deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable' | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null && \
                  sudo apt update && sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin && \
                  sudo usermod -aG docker \$USER"
            ;;
        nodejs)
            echo "curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - && \
                  sudo apt install -y nodejs || (sudo apt update && sudo apt install -y nodejs npm)"
            ;;
        python3)
            echo "sudo apt update && sudo apt install -y python3 python3-pip"
            ;;
        git)
            echo "sudo apt update && sudo apt install -y git"
            ;;
        ruby)
            echo "sudo apt update && sudo apt install -y ruby-full"
            ;;
        golang)
            echo "sudo apt update && sudo apt install -y golang"
            ;;
        rust)
            echo "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
            ;;

        # Media Applications
        vlc)
            echo "sudo apt update && sudo apt install -y vlc"
            ;;
        stremio)
            if [ "$type" = "snap" ]; then
                echo "sudo snap install stremio"
            else
                echo "echo 'Stremio requires snap or manual download from https://www.stremio.com/downloads' && exit 1"
            fi
            ;;

        # Communication Applications
        slack)
            if [ "$type" = "snap" ]; then
                echo "sudo snap install slack --classic"
            else
                echo "wget https://downloads.slack-edge.com/releases/linux/4.36.140/prod/x64/slack-desktop-4.36.140-amd64.deb -O /tmp/slack.deb && \
                      sudo dpkg -i /tmp/slack.deb || sudo apt-get install -f -y && \
                      rm -f /tmp/slack.deb"
            fi
            ;;
        discord)
            if [ "$type" = "snap" ]; then
                echo "sudo snap install discord"
            else
                echo "wget 'https://discord.com/api/download?platform=linux&format=deb' -O /tmp/discord.deb && \
                      sudo dpkg -i /tmp/discord.deb || sudo apt-get install -f -y && \
                      rm -f /tmp/discord.deb"
            fi
            ;;
        skype)
            if [ "$type" = "snap" ]; then
                echo "sudo snap install skype --classic"
            else
                echo "wget https://go.skype.com/skypeforlinux-64.deb -O /tmp/skype.deb && \
                      sudo dpkg -i /tmp/skype.deb || sudo apt-get install -f -y && \
                      rm -f /tmp/skype.deb"
            fi
            ;;

        # Graphics Applications
        gimp)
            echo "sudo apt update && sudo apt install -y gimp"
            ;;
        inkscape)
            echo "sudo apt update && sudo apt install -y inkscape"
            ;;

        # API Testing Tools
        postman)
            echo "sudo snap install postman"
            ;;
        insomnia)
            echo "sudo snap install insomnia"
            ;;

        # Office Suite
        libreoffice)
            echo "sudo apt update && sudo apt install -y libreoffice"
            ;;

        # Torrent Clients
        qbittorrent)
            echo "sudo apt update && sudo apt install -y qbittorrent"
            ;;
        transmission)
            echo "sudo apt update && sudo apt install -y transmission-gtk"
            ;;

        *)
            echo ""  # Return empty for unknown apps
            ;;
    esac
}
