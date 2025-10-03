#!/bin/bash

################################################################################
# BellNews Alarm Player Update Script
#
# This script adds the missing alarm player component to enable bell sounds
# on the Nano Pi hardware. Run this AFTER the main system installation.
#
# Usage: sudo bash update_alarm_player.sh
################################################################################

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log file
LOG_FILE="/var/log/bellnews_alarm_update.log"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Banner
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║     BellNews Alarm Player Update                             ║
║     Adding Sound Playback Component                          ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root: sudo bash update_alarm_player.sh"
    exit 1
fi

# Start logging
echo "==================================================" | tee "$LOG_FILE"
echo "BellNews Alarm Player Update - $(date)" | tee -a "$LOG_FILE"
echo "==================================================" | tee -a "$LOG_FILE"

# Detect installation directory
INSTALL_DIR=""
if [ -d "/root/bellapp" ]; then
    INSTALL_DIR="/root/bellapp"
elif [ -d "/home/bellapp" ]; then
    INSTALL_DIR="/home/bellapp"
elif [ -d "$(pwd)" ] && [ -f "$(pwd)/vcns_timer_web.py" ]; then
    INSTALL_DIR="$(pwd)"
else
    print_error "Cannot detect BellNews installation directory"
    print_status "Please cd to your bellapp directory and run this script again"
    exit 1
fi

print_success "Detected installation directory: $INSTALL_DIR"

# Change to installation directory
cd "$INSTALL_DIR"

# Check if alarm_player.py exists
if [ ! -f "$INSTALL_DIR/alarm_player.py" ]; then
    print_error "alarm_player.py not found in $INSTALL_DIR"
    print_status "Please ensure all update files are in the installation directory"
    exit 1
fi

print_status "Step 1/6: Installing audio dependencies..."
apt-get update >> "$LOG_FILE" 2>&1
apt-get install -y python3-dev libasound2-dev >> "$LOG_FILE" 2>&1
print_success "Audio dependencies installed"

print_status "Step 2/6: Installing simpleaudio Python library..."
pip3 install simpleaudio >> "$LOG_FILE" 2>&1 || {
    print_warning "pip3 install failed, trying with --break-system-packages"
    pip3 install --break-system-packages simpleaudio >> "$LOG_FILE" 2>&1
}
print_success "simpleaudio library installed"

print_status "Step 3/6: Setting up alarm player service file..."
# Copy service file to systemd directory
cp "$INSTALL_DIR/alarm_player.service" /etc/systemd/system/alarm_player.service

# Update paths in service file based on actual installation directory
sed -i "s|WorkingDirectory=.*|WorkingDirectory=$INSTALL_DIR|g" /etc/systemd/system/alarm_player.service
sed -i "s|ExecStart=.*|ExecStart=/usr/bin/python3 $INSTALL_DIR/alarm_player.py|g" /etc/systemd/system/alarm_player.service

print_success "Service file configured"

print_status "Step 4/6: Making alarm_player.py executable..."
chmod +x "$INSTALL_DIR/alarm_player.py"
print_success "Permissions set"

print_status "Step 5/6: Enabling and starting alarm player service..."
systemctl daemon-reload
systemctl enable alarm_player.service >> "$LOG_FILE" 2>&1
systemctl restart alarm_player.service >> "$LOG_FILE" 2>&1

# Wait a moment for service to start
sleep 2

# Check service status
if systemctl is-active --quiet alarm_player.service; then
    print_success "Alarm player service is running"
else
    print_warning "Alarm player service may not have started properly"
    print_status "Check status with: sudo systemctl status alarm_player"
fi

print_status "Step 6/6: Verifying installation..."

# Check if logs are being created
if [ -f "$INSTALL_DIR/logs/alarm_player.log" ]; then
    print_success "Alarm player log file created"
    tail -5 "$INSTALL_DIR/logs/alarm_player.log"
else
    print_warning "Log file not yet created (may take a few seconds)"
fi

# Final summary
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                               ║${NC}"
echo -e "${GREEN}║   UPDATE COMPLETE!                                            ║${NC}"
echo -e "${GREEN}║                                                               ║${NC}"
echo -e "${GREEN}║   The alarm player service is now installed and running      ║${NC}"
echo -e "${GREEN}║   Bell sounds will play through the Nano Pi speakers         ║${NC}"
echo -e "${GREEN}║                                                               ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
print_status "Useful commands:"
echo "  - Check service status:  sudo systemctl status alarm_player"
echo "  - View logs:             sudo journalctl -u alarm_player -f"
echo "  - Restart service:       sudo systemctl restart alarm_player"
echo "  - Stop service:          sudo systemctl stop alarm_player"
echo ""
print_status "Log file: $LOG_FILE"
print_status "Service log: $INSTALL_DIR/logs/alarm_player.log"
echo ""
print_success "You can now test alarms from the web interface!"
echo ""
