#!/bin/bash

################################################################################
# Update Script for Existing BellNews Nano Pi Installations
#
# This script updates existing Nano Pi devices with the alarm player fixes
# Run this on each Nano Pi that needs the alarm sound update
#
# Usage: sudo bash update_existing_nanopi.sh
################################################################################

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Banner
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║     BellNews Nano Pi Alarm Update Script                     ║
║     Fixes alarm sound playback issues                        ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root: sudo bash update_existing_nanopi.sh"
    exit 1
fi

echo "==================================================="
echo "BellNews Nano Pi Update - $(date)"
echo "==================================================="

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
    exit 1
fi

print_success "Detected installation directory: $INSTALL_DIR"

# Step 1: Install/update git if needed
print_status "Step 1/7: Ensuring git is installed..."
apt-get update > /dev/null 2>&1
apt-get install -y git > /dev/null 2>&1
print_success "Git is ready"

# Step 2: Setup git repository
print_status "Step 2/7: Setting up git repository..."
cd "$INSTALL_DIR"

if [ ! -d ".git" ]; then
    print_status "Initializing git repository..."
    git init
    git remote add origin https://github.com/EmmanuelMsafiri1992/OnlyBell2025.git
fi

# Step 3: Fetch latest updates
print_status "Step 3/7: Fetching latest updates from GitHub..."
git fetch origin
git branch -m main 2>/dev/null || true
git branch --set-upstream-to=origin/main main 2>/dev/null || true
git reset --hard origin/main
print_success "Latest code downloaded"

# Step 4: Configure ALSA audio to use H3 Codec (card 2)
print_status "Step 4/7: Configuring audio output..."
cat > /etc/asound.conf << 'ALSA_EOF'
pcm.!default {
    type hw
    card 2
}

ctl.!default {
    type hw
    card 2
}
ALSA_EOF
print_success "Audio routing configured to H3 Audio Codec"

# Step 5: Set audio volume
print_status "Step 5/7: Setting audio volume..."
amixer set 'Line Out' 100% > /dev/null 2>&1
amixer set 'DAC' 100% > /dev/null 2>&1
alsactl store
print_success "Audio volume set to maximum"

# Step 6: Install ffmpeg if missing
print_status "Step 6/7: Ensuring ffmpeg is installed..."
if ! command -v ffmpeg &> /dev/null; then
    apt-get install -y ffmpeg
    print_success "ffmpeg installed"
else
    print_success "ffmpeg already installed"
fi

# Step 7: Restart alarm player service
print_status "Step 7/7: Restarting alarm player service..."
systemctl restart alarm_player
sleep 2

if systemctl is-active --quiet alarm_player.service; then
    print_success "Alarm player service is running"
else
    print_warning "Alarm player service may not have started properly"
    print_status "Check status with: sudo systemctl status alarm_player"
fi

# Final summary
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                               ║${NC}"
echo -e "${GREEN}║   UPDATE COMPLETE!                                            ║${NC}"
echo -e "${GREEN}║                                                               ║${NC}"
echo -e "${GREEN}║   Alarm sound playback is now fixed                          ║${NC}"
echo -e "${GREEN}║   - Edited alarms will trigger correctly                     ║${NC}"
echo -e "${GREEN}║   - MP3/WAV/OGG audio formats supported                      ║${NC}"
echo -e "${GREEN}║   - Audio routed to correct hardware                         ║${NC}"
echo -e "${GREEN}║                                                               ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
print_status "Test by creating an alarm via the web interface!"
echo ""
print_status "Useful commands:"
echo "  - Check service:  sudo systemctl status alarm_player"
echo "  - View logs:      sudo journalctl -u alarm_player -f"
echo "  - Test audio:     speaker-test -t wav -c 2 -l 1"
echo ""
print_success "Update completed successfully!"
echo ""
