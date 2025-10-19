#!/bin/bash

################################################################################
# BellNews Network Auto-Start Fix
#
# Problem: Network interface (eth0) doesn't automatically get IP on boot
# Symptom: Need to manually run "sudo dhclient eth0" to get internet
# Cause: DHCP client not starting automatically, or network config incomplete
#
# This script ensures network ALWAYS starts on boot automatically
#
# Usage: sudo bash fix_network_autostart.sh
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Banner
echo -e "${PURPLE}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║     BellNews Network Auto-Start Fix                          ║
║     Ensure Network Always Starts on Boot                     ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"
echo ""

print_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root: sudo bash fix_network_autostart.sh"
    exit 1
fi

echo "Analyzing network configuration..."
echo ""

# Detect primary network interface
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
if [ -z "$INTERFACE" ]; then
    INTERFACE="eth0"
    print_warning "Could not detect interface, using default: eth0"
else
    print_success "Detected network interface: $INTERFACE"
fi

# Check current IP
CURRENT_IP=$(ip addr show "$INTERFACE" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
if [ -n "$CURRENT_IP" ]; then
    print_success "Current IP address: $CURRENT_IP"
else
    print_warning "No IP address currently assigned"
fi
echo ""

################################################################################
# STEP 1: Detect network configuration system
################################################################################
print_step "Detecting network configuration system..."
echo ""

NETWORK_SYSTEM=""

if [ -d "/etc/netplan" ] && ls /etc/netplan/*.yaml >/dev/null 2>&1; then
    NETWORK_SYSTEM="netplan"
    print_info "Found netplan configuration (Ubuntu 18.04+ style)"
elif [ -f "/etc/dhcpcd.conf" ]; then
    NETWORK_SYSTEM="dhcpcd"
    print_info "Found dhcpcd configuration (Raspberry Pi style)"
elif [ -f "/etc/network/interfaces" ]; then
    NETWORK_SYSTEM="interfaces"
    print_info "Found interfaces configuration (Debian style)"
else
    print_warning "Could not detect network configuration system"
    NETWORK_SYSTEM="systemd-networkd"
    print_info "Will use systemd-networkd as fallback"
fi
echo ""

################################################################################
# STEP 2: Fix network configuration based on detected system
################################################################################
print_step "Configuring network for auto-start..."
echo ""

case "$NETWORK_SYSTEM" in
    netplan)
        print_info "Configuring netplan for automatic DHCP..."

        # Backup existing config
        mkdir -p /etc/netplan/backup
        cp /etc/netplan/*.yaml /etc/netplan/backup/ 2>/dev/null || true

        # Create simple DHCP config
        cat > /etc/netplan/01-netcfg.yaml <<NETPLANCONFIG
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      dhcp4: true
      dhcp6: false
      optional: false
NETPLANCONFIG

        print_success "Created netplan configuration"
        print_info "Applying netplan configuration..."
        netplan apply
        print_success "Netplan applied"
        ;;

    dhcpcd)
        print_info "Configuring dhcpcd for automatic start..."

        # Backup existing config
        cp /etc/dhcpcd.conf /etc/dhcpcd.conf.backup.$(date +%Y%m%d_%H%M%S)

        # Ensure interface is configured
        if ! grep -q "^interface $INTERFACE" /etc/dhcpcd.conf; then
            echo "" >> /etc/dhcpcd.conf
            echo "# Auto-configured by BellNews" >> /etc/dhcpcd.conf
            echo "interface $INTERFACE" >> /etc/dhcpcd.conf
            print_success "Added interface configuration to dhcpcd.conf"
        fi

        # Enable and start dhcpcd
        systemctl enable dhcpcd
        systemctl restart dhcpcd
        print_success "dhcpcd service enabled and started"
        ;;

    interfaces)
        print_info "Configuring /etc/network/interfaces for automatic DHCP..."

        # Backup existing config
        cp /etc/network/interfaces /etc/network/interfaces.backup.$(date +%Y%m%d_%H%M%S)

        # Check if interface is already configured
        if ! grep -q "iface $INTERFACE inet dhcp" /etc/network/interfaces; then
            cat >> /etc/network/interfaces <<INTERFACESCONFIG

# Auto-configured by BellNews
auto $INTERFACE
iface $INTERFACE inet dhcp
INTERFACESCONFIG
            print_success "Added DHCP configuration to /etc/network/interfaces"
        else
            print_info "Interface already configured in /etc/network/interfaces"
        fi

        # Restart networking
        systemctl restart networking
        print_success "Networking service restarted"
        ;;

    systemd-networkd)
        print_info "Configuring systemd-networkd for automatic DHCP..."

        # Create network configuration directory
        mkdir -p /etc/systemd/network

        # Create DHCP configuration
        cat > /etc/systemd/network/20-wired.network <<NETWORKDCONFIG
[Match]
Name=$INTERFACE

[Network]
DHCP=yes
NETWORKDCONFIG

        print_success "Created systemd-networkd configuration"

        # Enable and start systemd-networkd
        systemctl enable systemd-networkd
        systemctl restart systemd-networkd
        print_success "systemd-networkd enabled and started"
        ;;
esac
echo ""

################################################################################
# STEP 3: Create network-ensure service (runs on every boot)
################################################################################
print_step "Creating network-ensure service for boot-time verification..."
echo ""

# This service ensures network is up on every boot
cat > /etc/systemd/system/network-ensure.service <<'NETWORKENSURE'
[Unit]
Description=Ensure Network Interface Gets IP on Boot
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 5
ExecStart=/bin/bash -c '\
    INTERFACE=$(ip route | grep default | awk "{print \$5}" | head -1); \
    if [ -z "$INTERFACE" ]; then INTERFACE="eth0"; fi; \
    if ! ip addr show $INTERFACE | grep -q "inet "; then \
        echo "Network interface $INTERFACE has no IP, requesting DHCP..."; \
        dhclient -r $INTERFACE 2>/dev/null || true; \
        dhclient $INTERFACE; \
        sleep 3; \
        if ip addr show $INTERFACE | grep -q "inet "; then \
            echo "Network interface $INTERFACE obtained IP successfully"; \
        else \
            echo "Warning: Could not obtain IP for $INTERFACE"; \
        fi; \
    else \
        echo "Network interface $INTERFACE already has IP address"; \
    fi'
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
NETWORKENSURE

systemctl daemon-reload
systemctl enable network-ensure.service
print_success "Network-ensure service created and enabled"
print_info "This service will check and fix network on every boot"
echo ""

################################################################################
# STEP 4: Ensure dhclient is installed
################################################################################
print_step "Ensuring DHCP client is installed..."
echo ""

if command -v dhclient >/dev/null 2>&1; then
    print_success "dhclient is installed"
else
    print_warning "dhclient not found, installing..."
    apt-get update -qq
    apt-get install -y isc-dhcp-client
    print_success "dhclient installed"
fi
echo ""

################################################################################
# STEP 5: Test network now
################################################################################
print_step "Testing network connectivity..."
echo ""

# Request new IP if needed
if [ -z "$CURRENT_IP" ]; then
    print_info "Requesting DHCP lease for $INTERFACE..."
    dhclient -r "$INTERFACE" 2>/dev/null || true
    dhclient "$INTERFACE"
    sleep 3
fi

# Check IP again
NEW_IP=$(ip addr show "$INTERFACE" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
if [ -n "$NEW_IP" ]; then
    print_success "Network interface has IP: $NEW_IP"
else
    print_error "Failed to obtain IP address"
    print_info "You may need to check network cable or router"
fi

# Test connectivity
if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
    print_success "Internet connectivity verified"
elif ping -c 1 -W 3 $(ip route | grep default | awk '{print $3}') >/dev/null 2>&1; then
    print_warning "Local network works but no internet"
else
    print_error "No network connectivity"
fi
echo ""

################################################################################
# STEP 6: Create helper script for manual fix
################################################################################
print_step "Creating helper script for manual network restart..."
echo ""

cat > /usr/local/bin/fix-network <<'FIXNETWORK'
#!/bin/bash
# Quick network fix script
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
if [ -z "$INTERFACE" ]; then
    INTERFACE="eth0"
fi

echo "Restarting network on $INTERFACE..."
dhclient -r "$INTERFACE" 2>/dev/null || true
dhclient "$INTERFACE"
sleep 2

IP=$(ip addr show "$INTERFACE" | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
if [ -n "$IP" ]; then
    echo "✓ Network is up - IP: $IP"
else
    echo "✗ Failed to get IP address"
fi
FIXNETWORK

chmod +x /usr/local/bin/fix-network
print_success "Created /usr/local/bin/fix-network helper script"
print_info "You can run 'sudo fix-network' if network fails in future"
echo ""

################################################################################
# SUMMARY
################################################################################
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║   ✓ NETWORK AUTO-START CONFIGURED!                          ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo -e "${CYAN}What Was Fixed:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✓${NC} Network System:      $NETWORK_SYSTEM"
echo -e "${GREEN}✓${NC} Interface:           $INTERFACE"
echo -e "${GREEN}✓${NC} Current IP:          ${NEW_IP:-None}"
echo -e "${GREEN}✓${NC} DHCP:                Enabled and configured"
echo -e "${GREEN}✓${NC} Boot Service:        network-ensure.service installed"
echo -e "${GREEN}✓${NC} Auto-Start:          YES - will start on every boot"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo -e "${YELLOW}What Happens on Next Reboot:${NC}"
echo "  1. System boots up"
echo "  2. Network services start automatically"
echo "  3. network-ensure.service checks if IP was obtained"
echo "  4. If no IP, automatically runs 'dhclient $INTERFACE'"
echo "  5. Network is always ready - NO manual intervention needed!"
echo ""

echo -e "${BLUE}Manual Commands (if ever needed):${NC}"
echo "  • Quick fix:           sudo fix-network"
echo "  • Manual DHCP:         sudo dhclient $INTERFACE"
echo "  • Check IP:            ip addr show $INTERFACE"
echo "  • Check service:       systemctl status network-ensure"
echo "  • View boot logs:      journalctl -u network-ensure"
echo ""

echo -e "${GREEN}✓ Network will now automatically start on every reboot!${NC}"
echo -e "${GREEN}✓ No more manual 'sudo dhclient eth0' needed!${NC}"
echo ""
