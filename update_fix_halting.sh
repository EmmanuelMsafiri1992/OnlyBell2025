#!/bin/bash

# Update script to fix application halting issues
# Run this script after pulling from GitHub on the NanoPi

set -e  # Exit on any error

echo "=========================================="
echo "OnlyBell Application Halting Fix Update"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    echo "Please run: sudo bash update_fix_halting.sh"
    exit 1
fi

# Define paths - detect where the app is installed
if [ -d "/opt/bellnews" ]; then
    APP_DIR="/opt/bellnews"
elif [ -d "/root/bellapp" ]; then
    APP_DIR="/root/bellapp"
else
    # Try to detect from current directory
    if [ -f "./alarm_player.py" ]; then
        APP_DIR="$(pwd)"
    else
        echo -e "${RED}Error: Cannot find application directory${NC}"
        echo "Looked in: /opt/bellnews, /root/bellapp"
        exit 1
    fi
fi

BACKUP_DIR="${APP_DIR}_backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "Using app directory: $APP_DIR"
echo ""

echo -e "${YELLOW}Step 1: Creating backup...${NC}"
mkdir -p "$BACKUP_DIR"
cp "$APP_DIR/alarm_player.py" "$BACKUP_DIR/alarm_player.py.$TIMESTAMP" 2>/dev/null || true
echo -e "${GREEN}✓ Backup created at: $BACKUP_DIR/alarm_player.py.$TIMESTAMP${NC}"
echo ""

echo -e "${YELLOW}Step 2: Stopping alarm_player service...${NC}"
if systemctl is-active --quiet alarm_player; then
    systemctl stop alarm_player
    echo -e "${GREEN}✓ Service stopped${NC}"
else
    echo -e "${YELLOW}Service was not running${NC}"
fi
echo ""

echo -e "${YELLOW}Step 3: Verifying Python dependencies...${NC}"
# Check if gc module is available (it's built-in, but let's verify Python works)
python3 -c "import gc; import os; import json; import time; print('All required modules available')" && \
    echo -e "${GREEN}✓ Python modules verified${NC}" || \
    (echo -e "${RED}✗ Python module check failed${NC}" && exit 1)
echo ""

echo -e "${YELLOW}Step 4: Checking for pygame or simpleaudio...${NC}"
if python3 -c "import pygame" 2>/dev/null; then
    echo -e "${GREEN}✓ pygame is installed${NC}"
elif python3 -c "import simpleaudio" 2>/dev/null; then
    echo -e "${GREEN}✓ simpleaudio is installed${NC}"
else
    echo -e "${YELLOW}⚠ No audio library found. Installing pygame...${NC}"
    pip3 install pygame || echo -e "${YELLOW}Warning: pygame installation failed, but continuing...${NC}"
fi
echo ""

echo -e "${YELLOW}Step 5: Verifying alarm_player.py updates...${NC}"
# Check if the new code is present
if grep -q "def should_reload_alarms" "$APP_DIR/alarm_player.py"; then
    echo -e "${GREEN}✓ File watching optimization detected${NC}"
else
    echo -e "${RED}✗ Updates not found in alarm_player.py${NC}"
    echo "Make sure you pulled the latest code from GitHub first!"
    exit 1
fi

if grep -q "gc.collect()" "$APP_DIR/alarm_player.py"; then
    echo -e "${GREEN}✓ Garbage collection optimization detected${NC}"
else
    echo -e "${RED}✗ Memory cleanup updates not found${NC}"
    exit 1
fi

if grep -q "pygame.mixer.music.unload()" "$APP_DIR/alarm_player.py"; then
    echo -e "${GREEN}✓ Pygame resource cleanup detected${NC}"
else
    echo -e "${YELLOW}⚠ Pygame cleanup not found (may be using simpleaudio instead)${NC}"
fi
echo ""

echo -e "${YELLOW}Step 6: Clearing old logs and temporary files...${NC}"
# Clean up old log files to free space
find "$APP_DIR/logs" -name "*.log.*" -mtime +7 -delete 2>/dev/null || true
echo -e "${GREEN}✓ Old logs cleaned${NC}"
echo ""

echo -e "${YELLOW}Step 7: Restarting alarm_player service...${NC}"
systemctl daemon-reload
systemctl start alarm_player
sleep 2

# Check if service started successfully
if systemctl is-active --quiet alarm_player; then
    echo -e "${GREEN}✓ Service started successfully${NC}"
else
    echo -e "${RED}✗ Service failed to start${NC}"
    echo "Checking logs..."
    journalctl -u alarm_player -n 20 --no-pager
    exit 1
fi
echo ""

echo -e "${YELLOW}Step 8: Verifying service health...${NC}"
sleep 3
if systemctl is-active --quiet alarm_player; then
    echo -e "${GREEN}✓ Service is running${NC}"
    echo ""
    echo "Recent service logs:"
    journalctl -u alarm_player -n 10 --no-pager
else
    echo -e "${RED}✗ Service is not running${NC}"
    exit 1
fi
echo ""

echo -e "${GREEN}=========================================="
echo "Update completed successfully!"
echo "==========================================${NC}"
echo ""
echo "The application has been updated with:"
echo "  • Smart file watching (only reload when alarms.json changes)"
echo "  • Periodic memory cleanup (every hour)"
echo "  • Pygame resource cleanup after sound playback"
echo "  • Enhanced logging for debugging"
echo ""
echo -e "${YELLOW}Monitoring commands:${NC}"
echo "  • Watch logs:        journalctl -u alarm_player -f"
echo "  • Service status:    systemctl status alarm_player"
echo "  • Restart service:   systemctl restart alarm_player"
echo ""
echo -e "${GREEN}The halting issue should now be resolved!${NC}"
echo ""
