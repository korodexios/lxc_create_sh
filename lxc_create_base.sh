#!/bin/bash
# ===============================================================================
# LXC Base Creation Script
# Creates basic LXC container (no Docker, no Portainer)
#
# Usage: bash /root/scripts/lxc_create_base.sh <ctid> <hostname> [template]
#        template: "debian-13" (default), "debian-12", "ubuntu-22.04", etc.
# ===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lxc_module_validation.sh"

# Colors
GREEN='\e[32m'
BLUE='\e[34m'
RED='\e[31m'
YELLOW='\e[33m'
RESET='\e[0m'

# Defaults (can be overridden by environment variables)
DEFAULT_ROOTFS_STORAGE="${LXC_ROOTFS_STORAGE:-local-lvm}"
DEFAULT_ROOTFS_SIZE="${LXC_ROOTFS_SIZE:-4}"
DEFAULT_CORES="${LXC_CORES:-2}"
DEFAULT_MEMORY="${LXC_MEMORY:-2048}"
DEFAULT_SWAP=0
DEFAULT_USER="${LXC_USER:-user}"
DEFAULT_EXTRA_USERS="${LXC_EXTRA_USERS:-}"
DEFAULT_PASS="${LXC_PASS:-123456}"
DEFAULT_BRIDGE="${LXC_BRIDGE:-vmbr0}"
DEFAULT_UNPRIVILEGED=1
DEFAULT_SSH_KEY="${LXC_SSH_KEY:-/root/.ssh/id_ed25519.pub}"

# ===============================================================================
# Functions
# ===============================================================================

get_newest_debian_template() {
    # Find newest Debian template (sort by version)
    local template=$(pveam list local 2>/dev/null | \
        grep "debian.*standard.*\.tar\.zst" | \
        sort -t'-' -k3 -V | \
        tail -1 | \
        awk '{print $1}')
    
    if [[ -z "$template" ]]; then
        # Fallback to any debian template
        template=$(pveam list local 2>/dev/null | \
            grep "debian.*standard" | \
            head -1 | \
            awk '{print $1}')
    fi
    
    echo "$template"
}

create_base_lxc() {
    local ctid=$1
    local hostname=$2
    local template_name=${3:-""}
    
    echo -e "${BLUE}=== Creating Base LXC ===${RESET}"
    echo "CTID: $ctid"
    echo "Hostname: $hostname"
    
    # Validate
    if ! validate_lxc_params "$ctid" "$hostname"; then
        return 1
    fi
    
    # Get template
    if [[ -z "$template_name" ]]; then
        template_name=$(get_newest_debian_template)
        echo -e "${GREEN}Using newest Debian: $template_name${RESET}"
    else
        # Find matching template
        template_name=$(pveam list local 2>/dev/null | \
            grep "$template_name" | \
            head -1 | \
            awk '{print $1}')
    fi
    
    if [[ -z "$template_name" ]]; then
        echo -e "${RED}Error: Template not found${RESET}"
        return 1
    fi
    
    echo "Template: $template_name"
    
    # Determine OS type
    local ostype="debian"
    if [[ "$template_name" == *"ubuntu"* ]]; then
        ostype="ubuntu"
    fi
    
    # Create
    echo -e "${BLUE}Creating LXC...${RESET}"
    pct create "$ctid" "$template_name" \
        --storage "$DEFAULT_ROOTFS_STORAGE" \
        --rootfs "volume=$DEFAULT_ROOTFS_STORAGE:$DEFAULT_ROOTFS_SIZE,mountoptions=noatime,acl=1" \
        --ostype "$ostype" \
        --arch amd64 \
        --password "$DEFAULT_PASS" \
        --unprivileged "$DEFAULT_UNPRIVILEGED" \
        --cores "$DEFAULT_CORES" \
        --memory "$DEFAULT_MEMORY" \
        --swap "$DEFAULT_SWAP" \
        --hostname "$hostname" \
        --net0 "name=eth0,bridge=$DEFAULT_BRIDGE,ip=dhcp,type=veth" \
        --features "nesting=1" \
        --description "primary_user=$DEFAULT_USER" \
        --start true
    
    if [[ -f "$DEFAULT_SSH_KEY" ]]; then
        echo -e "${BLUE}Injecting SSH key...${RESET}"
        # Validate SSH key content before injecting
        local ssh_key_content
        ssh_key_content=$(cat "$DEFAULT_SSH_KEY")
        if [[ ! "$ssh_key_content" =~ ^(ssh-rsa|ssh-ed25519|ssh-dss|ecdsa-) ]]; then
            echo -e "${RED}Error: SSH key file does not contain valid public key${RESET}"
            return 1
        fi
        pct exec "$ctid" -- bash -c "
            mkdir -p /root/.ssh
            chmod 700 /root/.ssh
        " < /dev/null
        pct exec "$ctid" -- bash -c "cat >> /root/.ssh/authorized_keys" < "$DEFAULT_SSH_KEY"
    fi
    
    # Získanie časovej zóny priamo z Proxmox hostitela
    HOST_TZ=$(cat /etc/timezone 2>/dev/null || echo "Europe/Bratislava")
    
    # Timezone setup (LXC shares host clock)
    echo -e "${BLUE}Setting timezone to $HOST_TZ...${RESET}"
    pct exec "$ctid" -- bash -c "
        echo '$HOST_TZ' > /etc/timezone
        ln -sf /usr/share/zoneinfo/$HOST_TZ /etc/localtime

        # Verify
        echo 'Current time:'
        date
        cat /etc/timezone
    "

    # Basic setup
    echo -e "${BLUE}Setting up system...${RESET}"
    pct exec "$ctid" -- bash -c "
        set -e

        # Generate locale FIRST to avoid perl warnings during apt
        sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen 2>/dev/null || true
        echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
        locale-gen en_US.UTF-8
        update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
        export LANG=en_US.UTF-8
        export LC_ALL=en_US.UTF-8

        apt-get update
        apt-get upgrade -y
        apt-get install -y sudo curl wget vim nano htop net-tools locales

        # Helper funkcia na vytvorenie používateľa a nastavenie SSH
        create_account() {
            local u="\$1"
            if ! id "\$u" &>/dev/null; then
                useradd -m -s /bin/bash "\$u"
                echo "User '\$u' created successfully"
            fi
            echo "\$u:$DEFAULT_PASS" | chpasswd
            usermod -aG sudo "\$u"

            if [ -f /root/.ssh/authorized_keys ]; then
                mkdir -p "/home/\$u/.ssh"
                cp /root/.ssh/authorized_keys "/home/\$u/.ssh/authorized_keys"
                chown -R "\$u:\$u" "/home/\$u/.ssh"
                chmod 700 "/home/\$u/.ssh"
                chmod 600 "/home/\$u/.ssh/authorized_keys"
            fi
        }

        # Create primary user only if defined
        if [[ -n "$DEFAULT_USER" ]]; then
            create_account "$DEFAULT_USER"
        fi

        # Create extra users if defined
        if [[ -n "$DEFAULT_EXTRA_USERS" ]]; then
            IFS=',' read -ra EXTRAS <<< "$DEFAULT_EXTRA_USERS"
            for extra in "\${EXTRAS[@]}"; do
                extra=\$(echo "\$extra" | tr -d ' ')
                if [[ -n "\$extra" ]]; then
                    create_account "\$extra"
                fi
            done
        fi
    "
    
    # Nastavíme description kontajnera v Proxmoxe pre ďalšie skripty
    if [[ -n "$DEFAULT_USER" ]]; then
        pct set "$ctid" --description "primary_user=$DEFAULT_USER"
    else
        pct set "$ctid" --description "primary_user=root"
    fi

    # Verify user was created properly
    echo -e "${BLUE}Verifying user '$DEFAULT_USER'...${RESET}"
    pct exec "$ctid" -- bash -c "
        if ! id '$DEFAULT_USER' &>/dev/null; then
            echo 'FATAL: User $DEFAULT_USER was not created!' >&2
            exit 1
        fi
        getent passwd '$DEFAULT_USER'
        echo 'User verified successfully'
    "
    
    # Verify time is correct
    echo -e "${BLUE}Verifying time...${RESET}"
    pct exec "$ctid" -- bash -c "
        echo ''
        echo '=== Final Time Check ==='
        date
        timedatectl | grep -E 'Time zone|synchronized'
    "

    # Get IP
    local ip
    ip=$(pct exec "$ctid" -- ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "not assigned")
    
    echo ""
    echo -e "${GREEN}=== Base LXC Created Successfully ===${RESET}"
    echo "CTID: $ctid"
    echo "Hostname: $hostname"
    echo "IP: $ip"
    echo "User: $DEFAULT_USER"
    echo "Password: $DEFAULT_PASS (change immediately!)"
    echo ""
    echo "Next steps:"
    echo "  - Install Docker: bash $SCRIPT_DIR/lxc_install_docker.sh $ctid"
    echo "  - Install Portainer: bash $SCRIPT_DIR/lxc_install_portainer.sh $ctid"
    echo "  - Both: bash $SCRIPT_DIR/lxc_install_docker_portainer.sh $ctid"
    
    return 0
}

# ===============================================================================
# Main
# ===============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 2 ]]; then
        echo "Usage: $0 <ctid> <hostname> [template]"
        echo ""
        echo "Arguments:"
        echo "  ctid      - Container ID (e.g., 100)"
        echo "  hostname  - Container hostname (e.g., docker-lxc)"
        echo "  template  - Optional: debian-13 (default), debian-12, ubuntu-22.04"
        echo ""
        echo "Examples:"
        echo "  $0 100 basic-lxc"
        echo "  $0 101 docker-lxc debian-13"
        echo "  $0 102 ubuntu-lxc ubuntu-22.04"
        exit 1
    fi
    
    create_base_lxc "$1" "$2" "${3:-}"
fi
