#!/bin/bash

################################################################################
# BellNews Connectivity Diagnostic and Recovery Script
#
# This script diagnoses and fixes common issues on Nano Pi:
# 1. SSH connectivity loss
# 2. Time sync failures after reboot
# 3. Network configuration problems
# 4. Journal disk space issues
# 5. Service status checks
#
# Usage: Run directly on NanoPi or via physical access if SSH is down
#        sudo bash diagnose_and_fix_connectivity.sh
################################################################################

set +e  # Continue on errors (we want to diagnose everything)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Log file
LOG_FILE="/tmp/bellnews_diagnostics_$(date +%Y%m%d_%H%M%S).log"
echo "BellNews Diagnostics Started: $(date)" > "$LOG_FILE"

# Banner
echo -e "${PURPLE}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║     BellNews Connectivity Diagnostic & Recovery Tool         ║
║     Diagnose and Fix Network/SSH/Time Issues                 ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Function to print colored output
print_header() {
    echo ""
    echo -e "${PURPLE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════════════${NC}"
    echo "$1" >> "$LOG_FILE"
}

print_step() {
    echo -e "${CYAN}[CHECK]${NC} $1"
    echo "[CHECK] $1" >> "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}  ✓${NC} $1"
    echo "  [OK] $1" >> "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}  ⚠${NC} $1"
    echo "  [WARNING] $1" >> "$LOG_FILE"
}

print_error() {
    echo -e "${RED}  ✗${NC} $1"
    echo "  [ERROR] $1" >> "$LOG_FILE"
}

print_info() {
    echo -e "${BLUE}  ℹ${NC} $1"
    echo "  [INFO] $1" >> "$LOG_FILE"
}

print_fix() {
    echo -e "${GREEN}[FIX]${NC} $1"
    echo "[FIX] $1" >> "$LOG_FILE"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root: sudo bash diagnose_and_fix_connectivity.sh"
    exit 1
fi

##############################################################################
# SECTION 1: SYSTEM TIME CHECK
##############################################################################
print_header "1. SYSTEM TIME AND DATE"

print_step "Checking current system time..."
CURRENT_TIME=$(date)
CURRENT_YEAR=$(date +%Y)
TIMEZONE=$(timedatectl 2>/dev/null | grep "Time zone" | awk '{print $3}')

print_info "Current time: $CURRENT_TIME"
print_info "Timezone: $TIMEZONE"

# Check if year is reasonable (should be 2025 or later)
if [ "$CURRENT_YEAR" -lt 2025 ]; then
    print_error "System time is incorrect! Year is $CURRENT_YEAR (should be 2025+)"

    print_fix "Attempting to fix time synchronization..."

    # Stop NTP temporarily
    systemctl stop ntp 2>/dev/null || systemctl stop systemd-timesyncd 2>/dev/null

    # Try multiple NTP servers using IP addresses (no DNS needed)
    print_info "Syncing with NTP servers..."
    if ntpdate -s -u 216.239.35.0 2>/dev/null; then
        print_success "Synced with Google NTP server (216.239.35.0)"
    elif ntpdate -s -u 129.6.15.28 2>/dev/null; then
        print_success "Synced with NIST NTP server (129.6.15.28)"
    elif ntpdate -s -u 132.163.96.1 2>/dev/null; then
        print_success "Synced with NIST NTP server (132.163.96.1)"
    else
        print_error "Failed to sync time with any NTP server"
        print_warning "Network may not be working - check network section below"
    fi

    # Restart NTP service
    systemctl start ntp 2>/dev/null || systemctl start systemd-timesyncd 2>/dev/null

    NEW_TIME=$(date)
    print_success "Time updated to: $NEW_TIME"
else
    print_success "System time appears correct"
fi

# Check if timesync-on-boot service exists
print_step "Checking boot time sync service..."
if systemctl list-unit-files | grep -q "timesync-on-boot.service"; then
    print_success "Boot time sync service is installed"

    if systemctl is-enabled timesync-on-boot.service 2>/dev/null | grep -q "enabled"; then
        print_success "Boot time sync is enabled"
    else
        print_warning "Boot time sync service is installed but not enabled"
        print_fix "Enabling boot time sync service..."
        systemctl enable timesync-on-boot.service
    fi
else
    print_warning "Boot time sync service NOT installed"
    print_info "Run fix_all_time_issues.sh to install it"
fi

##############################################################################
# SECTION 2: NETWORK CONNECTIVITY
##############################################################################
print_header "2. NETWORK CONNECTIVITY"

print_step "Checking network interfaces..."
INTERFACES=$(ip -br addr show | awk '{print $1}')
echo "$INTERFACES" | while read -r iface; do
    if [ "$iface" != "lo" ]; then
        STATUS=$(ip -br addr show "$iface" | awk '{print $2}')
        IP=$(ip -br addr show "$iface" | awk '{print $3}' | cut -d'/' -f1)

        if [ "$STATUS" = "UP" ]; then
            print_success "Interface $iface is UP - IP: $IP"
        else
            print_error "Interface $iface is $STATUS"
        fi
    fi
done

print_step "Checking default gateway..."
GATEWAY=$(ip route | grep default | awk '{print $3}')
if [ -n "$GATEWAY" ]; then
    print_success "Default gateway: $GATEWAY"

    # Test gateway connectivity
    if ping -c 1 -W 2 "$GATEWAY" >/dev/null 2>&1; then
        print_success "Gateway is reachable"
    else
        print_error "Gateway is NOT reachable"
        print_warning "Network cable may be disconnected or router is down"
    fi
else
    print_error "No default gateway configured"
    print_warning "Network is not properly configured"
fi

print_step "Checking DNS resolution..."
if nslookup google.com >/dev/null 2>&1; then
    print_success "DNS resolution is working"
else
    print_warning "DNS resolution failed"
    print_info "Checking /etc/resolv.conf..."

    if grep -q "nameserver" /etc/resolv.conf 2>/dev/null; then
        print_info "DNS servers configured: $(grep nameserver /etc/resolv.conf | awk '{print $2}' | tr '\n' ' ')"
    else
        print_error "No DNS servers configured in /etc/resolv.conf"
        print_fix "Adding Google DNS (8.8.8.8)..."
        echo "nameserver 8.8.8.8" >> /etc/resolv.conf
        print_success "Added Google DNS server"
    fi
fi

print_step "Checking internet connectivity..."
if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
    print_success "Internet connectivity is working"
else
    print_error "No internet connectivity"
    print_warning "Cannot reach external servers"
fi

##############################################################################
# SECTION 3: SSH SERVICE
##############################################################################
print_header "3. SSH SERVICE STATUS"

print_step "Checking SSH service..."
if systemctl is-active ssh >/dev/null 2>&1 || systemctl is-active sshd >/dev/null 2>&1; then
    print_success "SSH service is running"

    # Check if SSH is listening
    if netstat -tln 2>/dev/null | grep -q ":22 " || ss -tln 2>/dev/null | grep -q ":22 "; then
        print_success "SSH is listening on port 22"
    else
        print_error "SSH is running but not listening on port 22"
        print_fix "Restarting SSH service..."
        systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
    fi
else
    print_error "SSH service is NOT running"
    print_fix "Starting SSH service..."
    systemctl start ssh 2>/dev/null || systemctl start sshd 2>/dev/null
    systemctl enable ssh 2>/dev/null || systemctl enable sshd 2>/dev/null
    print_success "SSH service started and enabled"
fi

# Check SSH configuration
print_step "Checking SSH configuration..."
if [ -f /etc/ssh/sshd_config ]; then
    # Check if root login is permitted
    if grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config; then
        print_success "Root login is permitted"
    elif grep -q "^PermitRootLogin" /etc/ssh/sshd_config; then
        print_warning "Root login may be restricted"
    fi

    # Check if password authentication is enabled
    if grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config; then
        print_success "Password authentication is enabled"
    elif grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config; then
        print_warning "Password authentication is DISABLED"
        print_info "Only key-based authentication is allowed"
    fi
fi

##############################################################################
# SECTION 4: DISK SPACE
##############################################################################
print_header "4. DISK SPACE CHECK"

print_step "Checking overall disk usage..."
DISK_USAGE=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
DISK_FREE=$(df -h / | tail -1 | awk '{print $4}')

print_info "Disk usage: ${DISK_USAGE}% (${DISK_FREE} free)"

if [ "$DISK_USAGE" -gt 90 ]; then
    print_error "Disk is critically full (${DISK_USAGE}%)"
elif [ "$DISK_USAGE" -gt 80 ]; then
    print_warning "Disk is getting full (${DISK_USAGE}%)"
else
    print_success "Disk space is adequate (${DISK_USAGE}% used)"
fi

print_step "Checking journal disk usage..."
JOURNAL_SIZE=$(journalctl --disk-usage 2>/dev/null | grep -oP '\d+\.?\d*[KMG]' | tail -1)
print_info "Journal size: $JOURNAL_SIZE"

# Parse journal size and check if it's too large
JOURNAL_SIZE_BYTES=$(journalctl --disk-usage 2>/dev/null | grep -oP '\d+\.?\d*(?=[KMG])' | tail -1)
JOURNAL_UNIT=$(journalctl --disk-usage 2>/dev/null | grep -oP '[KMG]' | tail -1)

NEEDS_CLEANUP=false
if [ "$JOURNAL_UNIT" = "G" ]; then
    # If journal is in GB, it's too large
    NEEDS_CLEANUP=true
    print_warning "Journal is using ${JOURNAL_SIZE} - this is excessive"
elif [ "$JOURNAL_UNIT" = "M" ]; then
    # If journal is over 200MB, clean it up
    if [ "${JOURNAL_SIZE_BYTES%.*}" -gt 200 ]; then
        NEEDS_CLEANUP=true
        print_warning "Journal is using ${JOURNAL_SIZE} - should be cleaned"
    fi
fi

if [ "$NEEDS_CLEANUP" = true ]; then
    print_fix "Cleaning up journal logs..."

    # Clean logs older than 3 days
    journalctl --vacuum-time=3d

    # Limit journal size to 100MB
    journalctl --vacuum-size=100M

    NEW_JOURNAL_SIZE=$(journalctl --disk-usage 2>/dev/null | grep -oP '\d+\.?\d*[KMG]' | tail -1)
    print_success "Journal cleaned up - now using: $NEW_JOURNAL_SIZE"

    # Check if journald config needs updating
    if [ -f /etc/systemd/journald.conf ]; then
        if ! grep -q "^SystemMaxUse=100M" /etc/systemd/journald.conf; then
            print_info "Run fix_journal_disk_space.sh to permanently limit journal size"
        fi
    fi
else
    print_success "Journal size is acceptable"
fi

##############################################################################
# SECTION 5: BELLNEWS SERVICES
##############################################################################
print_header "5. BELLNEWS SERVICES STATUS"

# Detect installation directory
INSTALL_DIR=""
if [ -d "/opt/bellnews" ]; then
    INSTALL_DIR="/opt/bellnews"
elif [ -d "/root/bellapp" ]; then
    INSTALL_DIR="/root/bellapp"
elif [ -d "/home/bellapp" ]; then
    INSTALL_DIR="/home/bellapp"
fi

if [ -n "$INSTALL_DIR" ]; then
    print_success "BellNews installation found: $INSTALL_DIR"
else
    print_warning "BellNews installation directory not found"
fi

# Check web service
print_step "Checking BellNews web service..."
WEB_SERVICE=""
for svc in bellnews.service timer_web.service timerapp.service; do
    if systemctl list-unit-files | grep -q "$svc"; then
        WEB_SERVICE=$svc
        break
    fi
done

if [ -n "$WEB_SERVICE" ]; then
    if systemctl is-active "$WEB_SERVICE" >/dev/null 2>&1; then
        print_success "Web service ($WEB_SERVICE) is running"
    else
        print_error "Web service ($WEB_SERVICE) is NOT running"
        print_fix "Starting web service..."
        systemctl restart "$WEB_SERVICE"
    fi
else
    print_warning "Web service not found"
fi

# Check alarm player service
print_step "Checking alarm player service..."
if systemctl list-unit-files | grep -q "alarm_player.service"; then
    if systemctl is-active alarm_player.service >/dev/null 2>&1; then
        print_success "Alarm player service is running"
    else
        print_error "Alarm player service is NOT running"
        print_fix "Starting alarm player service..."
        systemctl restart alarm_player.service
    fi
else
    print_warning "Alarm player service not found"
fi

##############################################################################
# SECTION 6: SYSTEM RESOURCES
##############################################################################
print_header "6. SYSTEM RESOURCES"

print_step "Checking memory usage..."
MEM_TOTAL=$(free -m | grep Mem | awk '{print $2}')
MEM_USED=$(free -m | grep Mem | awk '{print $3}')
MEM_FREE=$(free -m | grep Mem | awk '{print $4}')
MEM_PERCENT=$((MEM_USED * 100 / MEM_TOTAL))

print_info "Memory: ${MEM_USED}MB / ${MEM_TOTAL}MB used (${MEM_PERCENT}%)"

if [ "$MEM_PERCENT" -gt 90 ]; then
    print_warning "Memory usage is very high (${MEM_PERCENT}%)"
elif [ "$MEM_PERCENT" -gt 80 ]; then
    print_warning "Memory usage is high (${MEM_PERCENT}%)"
else
    print_success "Memory usage is normal (${MEM_PERCENT}%)"
fi

print_step "Checking system load..."
LOAD=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
print_info "Load average: $LOAD"

print_step "Checking uptime..."
UPTIME=$(uptime -p 2>/dev/null || uptime | awk '{print $3,$4}')
print_info "System uptime: $UPTIME"

##############################################################################
# SUMMARY
##############################################################################
print_header "DIAGNOSTIC SUMMARY"

echo ""
echo -e "${CYAN}Quick Status Overview:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Time
if [ "$CURRENT_YEAR" -ge 2025 ]; then
    echo -e "${GREEN}✓${NC} System Time:        $CURRENT_TIME"
else
    echo -e "${RED}✗${NC} System Time:        INCORRECT - $CURRENT_TIME"
fi

# Network
if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Internet:           Connected"
else
    echo -e "${RED}✗${NC} Internet:           Disconnected"
fi

# SSH
if systemctl is-active ssh >/dev/null 2>&1 || systemctl is-active sshd >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} SSH Service:        Running"
else
    echo -e "${RED}✗${NC} SSH Service:        Stopped"
fi

# Disk
if [ "$DISK_USAGE" -lt 80 ]; then
    echo -e "${GREEN}✓${NC} Disk Space:         ${DISK_USAGE}% used (${DISK_FREE} free)"
else
    echo -e "${YELLOW}⚠${NC} Disk Space:         ${DISK_USAGE}% used (${DISK_FREE} free)"
fi

# Services
if [ -n "$WEB_SERVICE" ] && systemctl is-active "$WEB_SERVICE" >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Web Service:        Running"
elif [ -n "$WEB_SERVICE" ]; then
    echo -e "${RED}✗${NC} Web Service:        Stopped"
else
    echo -e "${YELLOW}⚠${NC} Web Service:        Not Found"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo -e "${YELLOW}Recommended Actions:${NC}"
echo ""

# Check what needs to be done
ACTIONS_NEEDED=false

if [ "$CURRENT_YEAR" -lt 2025 ]; then
    echo "  1. Fix system time:"
    echo "     sudo bash fix_all_time_issues.sh"
    ACTIONS_NEEDED=true
fi

if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    echo "  2. Check network cable and router"
    echo "     Verify network configuration in /etc/netplan or /etc/network/interfaces"
    ACTIONS_NEEDED=true
fi

if [ "$DISK_USAGE" -gt 80 ] || [ "$NEEDS_CLEANUP" = true ]; then
    echo "  3. Clean up disk space:"
    echo "     sudo bash fix_journal_disk_space.sh"
    ACTIONS_NEEDED=true
fi

if ! systemctl is-active ssh >/dev/null 2>&1 && ! systemctl is-active sshd >/dev/null 2>&1; then
    echo "  4. SSH service is stopped - it has been restarted"
    ACTIONS_NEEDED=true
fi

if [ "$ACTIONS_NEEDED" = false ]; then
    echo -e "${GREEN}  ✓ No issues detected - system appears healthy!${NC}"
fi

echo ""
echo -e "${GREEN}✓ Log file saved to: $LOG_FILE${NC}"
echo ""

print_success "Diagnostic complete!"
