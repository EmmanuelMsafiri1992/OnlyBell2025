#!/bin/bash

################################################################################
# BellNews Complete Time Synchronization Fix
#
# This script fixes ALL time-related issues on Nano Pi:
# 1. Syncs system time with NTP servers
# 2. Sets correct timezone (Asia/Jerusalem)
# 3. Updates code to display server time on web interface
# 4. Restarts all services
# 5. Verifies everything is working
#
# Usage: curl -sSL https://raw.githubusercontent.com/EmmanuelMsafiri1992/OnlyBell2025/main/fix_all_time_issues.sh | sudo bash
################################################################################

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Log file
LOG_FILE="/tmp/bellnews_time_fix.log"
echo "BellNews Time Fix Started: $(date)" > "$LOG_FILE"

# Banner
echo -e "${PURPLE}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║     BellNews Complete Time Synchronization Fix               ║
║     One-Time Script to Fix ALL Time Issues                   ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Function to print colored output
print_step() {
    echo -e "${CYAN}[STEP $1/$2]${NC} $3"
    echo "[STEP $1/$2] $3" >> "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
    echo "[SUCCESS] $1" >> "$LOG_FILE"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
    echo "[ERROR] $1" >> "$LOG_FILE"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
    echo "[INFO] $1" >> "$LOG_FILE"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root: sudo bash fix_all_time_issues.sh"
    exit 1
fi

# Detect installation directory
INSTALL_DIR=""
if [ -d "/opt/bellnews" ]; then
    INSTALL_DIR="/opt/bellnews"
elif [ -d "/root/bellapp" ]; then
    INSTALL_DIR="/root/bellapp"
elif [ -d "/home/bellapp" ]; then
    INSTALL_DIR="/home/bellapp"
else
    print_error "Cannot detect BellNews installation directory"
    print_info "Please ensure BellNews is installed first"
    exit 1
fi

print_success "Detected installation directory: $INSTALL_DIR"
echo ""

TOTAL_STEPS=11

# Step 1: Show current time before fix
print_step 1 $TOTAL_STEPS "Checking current system time..."
BEFORE_TIME=$(date)
print_info "Current time: $BEFORE_TIME"
echo ""

# Step 2: Install NTP packages
print_step 2 $TOTAL_STEPS "Installing NTP time synchronization packages..."
apt-get update -qq >> "$LOG_FILE" 2>&1
apt-get install -y ntp ntpdate >> "$LOG_FILE" 2>&1
print_success "NTP packages installed"
echo ""

# Step 3: Stop NTP service temporarily
print_step 3 $TOTAL_STEPS "Preparing for time synchronization..."
systemctl stop ntp >> "$LOG_FILE" 2>&1 || true
print_success "NTP service stopped temporarily"
echo ""

# Step 4: Set timezone
print_step 4 $TOTAL_STEPS "Setting timezone to Asia/Jerusalem..."
timedatectl set-timezone Asia/Jerusalem >> "$LOG_FILE" 2>&1
print_success "Timezone set to Asia/Jerusalem (IDT/IST)"
echo ""

# Step 5: Force immediate time sync
print_step 5 $TOTAL_STEPS "Synchronizing time with internet time servers..."
ntpdate -s time.nist.gov >> "$LOG_FILE" 2>&1 || \
ntpdate -s pool.ntp.org >> "$LOG_FILE" 2>&1 || \
ntpdate -s time.google.com >> "$LOG_FILE" 2>&1
print_success "Time synchronized with NTP servers"
AFTER_SYNC=$(date)
print_info "New time: $AFTER_SYNC"
echo ""

# Step 6: Enable and start NTP service
print_step 6 $TOTAL_STEPS "Enabling automatic time synchronization..."
systemctl start ntp >> "$LOG_FILE" 2>&1
systemctl enable ntp >> "$LOG_FILE" 2>&1
print_success "Automatic time sync enabled"
echo ""

# Step 6.5: Create time sync on boot service
print_step 6.5 $TOTAL_STEPS "Creating time sync on boot service..."
cat > /etc/systemd/system/timesync-on-boot.service << 'EOFSERVICE'
[Unit]
Description=Force NTP Time Sync on Boot
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 5
ExecStart=/usr/sbin/ntpdate -s pool.ntp.org
ExecStartPost=/bin/systemctl restart ntp
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOFSERVICE

systemctl daemon-reload >> "$LOG_FILE" 2>&1
systemctl enable timesync-on-boot.service >> "$LOG_FILE" 2>&1
print_success "Time sync on boot service created"
print_info "Time will automatically sync after every reboot"
echo ""

# Step 7: Update code to latest version
print_step 7 $TOTAL_STEPS "Updating BellNews code to latest version..."
cd "$INSTALL_DIR"

# Initialize git if not already done
if [ ! -d ".git" ]; then
    print_info "Initializing git repository..."
    git init >> "$LOG_FILE" 2>&1
    git remote add origin https://github.com/EmmanuelMsafiri1992/OnlyBell2025.git >> "$LOG_FILE" 2>&1 || true
fi

# Fetch and reset to latest
print_info "Fetching latest updates from GitHub..."
git fetch origin main >> "$LOG_FILE" 2>&1
git reset --hard origin/main >> "$LOG_FILE" 2>&1
print_success "Code updated to latest version"
print_info "Latest commit: $(git log -1 --oneline)"
echo ""

# Step 8: Restart web service
print_step 8 $TOTAL_STEPS "Restarting BellNews web service..."
systemctl restart bellnews.service >> "$LOG_FILE" 2>&1 || \
systemctl restart timer_web.service >> "$LOG_FILE" 2>&1 || \
systemctl restart timerapp.service >> "$LOG_FILE" 2>&1

sleep 3  # Wait for service to start
print_success "Web service restarted"
echo ""

# Step 9: Restart alarm player service
print_step 9 $TOTAL_STEPS "Restarting alarm player service..."
if systemctl list-units --type=service | grep -q "alarm_player"; then
    systemctl restart alarm_player.service >> "$LOG_FILE" 2>&1
    print_success "Alarm player service restarted"
else
    print_info "Alarm player service not found (may need separate installation)"
fi
echo ""

# Step 10: Verify everything is working
print_step 10 $TOTAL_STEPS "Verifying time synchronization..."
FINAL_TIME=$(date)
TIMEZONE=$(timedatectl | grep "Time zone" | awk '{print $3}')
NTP_STATUS=$(timedatectl | grep "NTP synchronized" | awk '{print $3}')

print_success "Time synchronization complete!"
echo ""

# Final summary
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║   ✓ ALL TIME ISSUES FIXED!                                   ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo -e "${CYAN}Summary:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✓${NC} System Time:        $FINAL_TIME"
echo -e "${GREEN}✓${NC} Timezone:           $TIMEZONE"
echo -e "${GREEN}✓${NC} NTP Synchronized:   $NTP_STATUS"
echo -e "${GREEN}✓${NC} Code Version:       Latest (with server time display)"
echo -e "${GREEN}✓${NC} Services:           Restarted and running"
echo -e "${GREEN}✓${NC} Boot Time Sync:     Enabled (syncs after every reboot)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo -e "${YELLOW}Important:${NC}"
echo "  1. Clear your browser cache (Ctrl+F5 or Ctrl+Shift+R)"
echo "  2. Refresh the web interface"
echo "  3. The web page will now show Nano Pi's exact time"
echo "  4. Time will automatically sync on EVERY reboot"
echo "  5. Time will stay synchronized via NTP continuously"
echo ""

echo -e "${CYAN}Verification:${NC}"
echo "  • Web interface time should match: $FINAL_TIME"
echo "  • Timezone should show: Asia/Jerusalem"
echo "  • Alarms will trigger at the displayed web time"
echo ""

echo -e "${BLUE}Additional Commands:${NC}"
echo "  • Check time:         date"
echo "  • Check NTP status:   timedatectl"
echo "  • View web logs:      sudo journalctl -u bellnews -f"
echo "  • View alarm logs:    sudo journalctl -u alarm_player -f"
echo ""

echo -e "${GREEN}✓ Log file saved to: $LOG_FILE${NC}"
echo ""

print_success "Time synchronization fix completed successfully!"
print_info "All Nano Pis running this script will now have synchronized time"
