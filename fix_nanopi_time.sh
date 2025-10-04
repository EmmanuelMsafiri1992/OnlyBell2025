#!/bin/bash

################################################################################
# Fix Nano Pi Time Synchronization
#
# Ensures Nano Pi time matches real-world time (Jerusalem timezone)
# Run this on Nano Pi: sudo bash fix_nanopi_time.sh
################################################################################

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Nano Pi Time Synchronization Fix                     ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}Please run as root: sudo bash fix_nanopi_time.sh${NC}"
    exit 1
fi

echo -e "${BLUE}[1/5]${NC} Current system time:"
date
echo ""

echo -e "${BLUE}[2/5]${NC} Setting timezone to Asia/Jerusalem..."
timedatectl set-timezone Asia/Jerusalem
echo -e "${GREEN}✓ Timezone set to Asia/Jerusalem${NC}"
echo ""

echo -e "${BLUE}[3/5]${NC} Installing NTP time sync..."
apt-get update -qq
apt-get install -y ntp ntpdate -qq
echo -e "${GREEN}✓ NTP installed${NC}"
echo ""

echo -e "${BLUE}[4/5]${NC} Syncing time with internet time servers..."
# Stop NTP service temporarily
systemctl stop ntp 2>/dev/null || true

# Force immediate sync with multiple time servers
ntpdate -s time.windows.com || \
ntpdate -s pool.ntp.org || \
ntpdate -s 0.pool.ntp.org || \
ntpdate -s time.nist.gov

echo -e "${GREEN}✓ Time synchronized${NC}"
echo ""

echo -e "${BLUE}[5/5]${NC} Enabling automatic time sync..."
# Configure NTP
cat > /etc/ntp.conf << 'EOF'
# NTP Configuration for Nano Pi
driftfile /var/lib/ntp/ntp.drift

# Use public NTP servers
server 0.pool.ntp.org iburst
server 1.pool.ntp.org iburst
server 2.pool.ntp.org iburst
server 3.pool.ntp.org iburst

# Fallback to local time if network is unavailable
server 127.127.1.0
fudge 127.127.1.0 stratum 10

# Access control
restrict -4 default kod notrap nomodify nopeer noquery limited
restrict -6 default kod notrap nomodify nopeer noquery limited
restrict 127.0.0.1
restrict ::1

# Enable statistics
statistics loopstats peerstats clockstats
filegen loopstats file loopstats type day enable
filegen peerstats file peerstats type day enable
filegen clockstats file clockstats type day enable
EOF

# Start NTP service
systemctl enable ntp
systemctl start ntp

# Enable systemd timesyncd as backup
timedatectl set-ntp true

echo -e "${GREEN}✓ Automatic time sync enabled${NC}"
echo ""

# Wait a moment for sync
sleep 2

echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Time Sync Complete!                                   ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${BLUE}Current time:${NC}"
date
echo ""

echo -e "${BLUE}Timezone:${NC}"
timedatectl | grep "Time zone"
echo ""

echo -e "${BLUE}NTP sync status:${NC}"
timedatectl | grep "NTP synchronized"
echo ""

echo -e "${GREEN}✓ Nano Pi time is now synchronized!${NC}"
echo -e "${BLUE}Time will automatically stay in sync via NTP${NC}"
echo ""
