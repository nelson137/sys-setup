#!/bin/bash

dir="$(dirname "$0")/files"



# Cache passwords
cache_passwds() {
    sudo echo >/dev/null
    read -rp 'Github password: ' GITHUB_PASSWD
}



# Make new user
mk_user() {
    sudo useradd nelson -mc 'Nelson Earle' -UG pi,adm,sudo,users
}



# Set new passwords for root, pi, and nelson
set_passwds() {
    local root pi nelson

    read -rp 'New password for root: ' root
    read -rp 'New password for pi: ' pi
    read -rp 'New password for nelson: ' nelson

    echo -e "root:${root}\npi:${pi}\nnelson:${nelson}" | sudo chpasswd
}



# Update, upgrade, install, and reinstall packages
pkgs() {
    # Pip installations
    pip install flake8 flake8-docstrings isort pycodestyle

    # Make sure apt-add-repository is installed
    which add-apt-repository >/dev/null ||
        sudo apt install -y apt-add-repository

    # PPAs
    sudo add-apt-repository -y ppa:nextcloud-devs/client

    # Update and upgrade
    sudo apt update

    sudo apt purge -y openssh-server

    # Installations
    sudo apt install -y apache2 boxes build-essential cmake dnsutils figlet \
        git html-xml-utils jq libsecret-tools lolcat nextcloud-client nmap \
        nodejs openssh-server phantomjs python3-flask python3-pip shellinabox \
        tmux upower vim w3m zsh

    # youtube-dl
    # Don't install from repositories because they are behind
    local url='https://yt-dl.org/downloads/latest/youtube-dl'
    sudo curl -sSL "$url" -o /usr/local/bin/youtube-dl
    sudo chmod a+rx /usr/local/bin/youtube-dl
}



# System config
system() {
    # Timezone
    sudo timedatectl set-timezone America/Chicago

    # Don't autologin
    sudo sed -ri 's/^(autologin-user=)/#\1/' /etc/lightdm/lightdm.conf

    # Disable splash screen on boot
    # - Removes arguments from the boot cmdline
    sed -i 's/ quiet//' /boot/cmdline.txt
    sed -i 's/ splash//' /boot/cmdline.txt
    sed -i 's/ plymouth.ignore-serial-consoles//' /boot/cmdline.txt

    # Turn off bluetooth on boot
    # - Add rfkill block bluetooth to rc.local
    [[ ! -f /etc/rc.local ]] &&
       echo -e "#!/bin/bash\n\nexit 0" | sudo tee /etc/rc.local >/dev/null
    local line_n="$(sudo cat /etc/rc.local | grep -n exit | cut -d: -f1)"
    sudo sed -i "${line_n}i rfkill block bluetooth\n" /etc/rc.local

    # Shellinabox
    # - Add --disable-ssl and --localhost-only to SHELLINABOX_ARGS
    # - Make shellinabox css file names more standardized
    # - Enable white-on-black (fg-on-bg) and color-terminal
    # - Restart shellinabox service
    local old_cwd="$(pwd)"
    local siab_args='--no-beep --disable-ssl --localhost-only'
    sudo sed -i "s/--no-beep/${siab_args}/" /etc/default/shellinabox
    cd /etc/shellinabox/options-enabled
    sudo rm *.css
    cd ../options-available
    sudo mv '00+Black on White.css' '00_black-on-white.css'
    sudo mv '00_White On Black.css' '00+white-on-black.css'
    sudo mv '01+Color Terminal.css' '01+color-terminal.css'
    sudo mv '01_Monochrome.css' '01_monochrome.css'
    cd ../options-enabled
    sudo ln -s '../options-available/00+white-on-black.css' .
    sudo ln -s '../options-available/01+color-terminal.css' .
    sudo systemctl restart shellinabox.service
    cd "$old_cwd"

    # Apache2
    # - Add another Listen command (below the first one) in ports.conf
    # - Copy shellinabox.conf to /etc/apache2/sites-available/
    # - Enable the proxy and proxy_http modules
    # - Enable shellinabox.conf
    # - Restart the apache2 service
    local n="$(cat /etc/apache2/ports.conf | grep -n Listen | cut -d: -f1)"
    ((n++))
    sudo sed -i "${n}i Listen 6184"
    sudo cp "${dir}/shellinabox.conf" /etc/apache2/sites-available/
    sudo a2enmod proxy proxy_http
    sudo a2ensite shellinabox.conf
    sudo systemctl restart apache2.service
}



# User and root crontabs
crontabs() {
    # Set crontab editor to vim basic
    cp "${dir}/files/.selected_editor" ~nelson/

    local comments="$(cat "${dir}/files/comments.crontab")"
    local mailto="MAILTO=''"

    # User crontab
    local dot="-C dot='~/Projects/Git/dot'"
    local u_tab='0 5 * * * [[ $(git "$dot" status -s) ]] || git "$dot" pull'
    echo -e "${comments}\n\n${mailto}\n\n${dot}\n${u_tab}" | crontab -

    # Root crontab
    sudo cp "${dir}/files/pretty-header-data.sh" /root/
    sudo chmod +x /root/pretty-header-data.sh
    local p="'/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'"
    local r_tab='*/10 * * * * /root/pretty-header-data.sh'
    echo -e "${comments}\n\nPATH=${p}\n${mailto}\n\n${r_tab}" | sudo crontab -
}



# User directory and environment
user() {
    # User directory
    mkdir -p ~nelson/{Downloads,Projects/Git}
    chown -R nelson:nelson ~nelson/
    git clone 'https://github.com/nelson137/dot.git' ~nelson/Projects/Git/dot

    # git
    # - Copy .gitconfig to ~nelson/
    # - Copy /usr/share/git-core/templates/ to ~nelson/.git_templates/
    # - Copy commit-msg to ~nelson/.git_templates/
    cp "${dir}/files/.gitconfig" ~nelson/
    sudo cp -r /usr/share/git-core/templates/ ~nelson/.git_templates/
    sudo chown -R nelson:nelson ~nelson/.git_templates/
    cp "${dir}/files/commit-msg" ~nelson/.git_templates/hooks/
    chmod a+x ~nelson/.git_templates/hooks/commit-msg

    # Oh My Zsh
    local url='https://github.com/robbyrussell/oh-my-zsh.git'
    git clone --depth=1 "$url" ~nelson/.oh-my-zsh
    sudo chsh nelson -s /usr/bin/zsh

    # LXPanel
    # - Remove widgets from the lxpanel
    # - Remove cached menu items so updates will appear
    # - Restart lxpanel
    cp "${dir}/files/panel" ~nelson/.config/lxpanel/LXDE-pi/panels/
    killall lxpanel
    find ~nelson/.cache/menus -type f -name '*' -print0 | xargs -0 rm
    nohup lxpanel -p LXDE & disown

    # LXTerminal
    # - Use the xterm color palette
    # - Cursor blinks
    # - Hide scroll bar
    local conf_file=~nelson/.config/lxterminal/lxterminal.conf
    sed -i '/^color_present=/ s/VGA/xterm/' "$conf_file"
    sed -i '/^cursorblinks=/ s/false/true/' "$conf_file"
    sed -i '/^hidescrollbar=/ s/false/true/' "$conf_file"

    # Make sure all files and directories are owned by nelson
    sudo chown -R nelson:nelson ~nelson
}



# Generate a new SSH key, replace the old Github key with the new one
git_ssh_key() {
    curl_git() {
        # Query Github API
        local url="https://api.github.com$1"
        shift
        curl -sSLiu "nelson137:$GITHUB_PASSWD" "$@" "$url"
    }

    # Generate SSH key
    local email='nelson.earle137@gmail.com'
    ssh-keygen -t rsa -b 4096 -C "$email" -f ~nelson/.ssh/id_rsa -N ''

    # For each ssh key
    # - Get more data about the key
    # - If the key's title is Pi
    #   - Delete it and upload the new one
    local -a key_ids=(
        $(curl_git '/users/nelson137/keys' | awk '/^\[/,/^\]/' | jq '.[].id')
    )
    local ssh_key="$(cat ~nelson/.ssh/id_rsa.pub)"
    for id in "${key_ids[@]}"; do
        local json="$(curl_git "/user/keys/$id" | awk '/^\{/,/^\}/')"
        if [[ $(echo "$json" | jq -r '.title') == Pi ]]; then
            curl_git "/user/keys/$id" -X DELETE
            curl_git '/user/keys' -d '{ "title": "Pi", "key": "'"$ssh_key"'" }'
            break
        fi
    done
}



cache_passwds
mk_user
set_passwds
pkgs
system
crontabs
user
git_ssh_key
