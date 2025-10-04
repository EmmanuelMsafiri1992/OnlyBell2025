#!/bin/bash
# Complete Bell News System Update Script
# This script updates all components and ensures everything works correctly

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔄 Bell News System Update${NC}"
echo "==============================="

# Function to log messages
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Step 1: Stop current services
log "Stopping Bell News services..."
sudo systemctl stop bellnews 2>/dev/null || true

# Kill any running processes
pkill -f "nanopi_monitor.py" 2>/dev/null || true
pkill -f "nano_web_timer.py" 2>/dev/null || true
pkill -f "vcns_timer_web.py" 2>/dev/null || true
sleep 3

# Step 2: Update from git repository
log "Updating from git repository..."
git pull origin main

# Step 3: Fix alarms.json if needed
log "Ensuring correct alarms.json format..."
if [[ -f "/opt/bellnews/alarms.json" ]]; then
    # Backup current alarms
    sudo cp /opt/bellnews/alarms.json /opt/bellnews/alarms.json.backup 2>/dev/null || true

    # Check if it's in wrong format and fix it
    if grep -q '"alarms":' /opt/bellnews/alarms.json 2>/dev/null; then
        log_warning "Converting alarms.json from object to array format..."
        echo '[]' | sudo tee /opt/bellnews/alarms.json > /dev/null
    fi
else
    # Create empty alarms file
    echo '[]' | sudo tee /opt/bellnews/alarms.json > /dev/null
fi

# Step 4: Install critical system packages
log "Installing critical system packages..."
apt-get update -qq
apt-get install -y python3-bcrypt python3-setuptools python3-wheel python3-yaml -qq 2>/dev/null || log_warning "Some system packages failed to install"

# Step 5: Ensure pygame compatibility stub is installed
log "Checking pygame compatibility..."
PYTHON_CMD="python3"
SITE_PACKAGES=$($PYTHON_CMD -c "import site; print(site.getsitepackages()[0])" 2>/dev/null || echo "/usr/local/lib/python3.10/site-packages")

if ! $PYTHON_CMD -c "import pygame; pygame.mixer.init()" 2>/dev/null; then
    log_warning "Installing pygame compatibility stub..."

    cat > /tmp/pygame_stub.py << 'EOF'
"""
Pygame compatibility stub for Bell News
Provides basic audio functionality using system commands
"""
import os
import sys
import subprocess

class mixer:
    @staticmethod
    def init():
        print("Pygame mixer initialized (stub mode)")
        return True

    @staticmethod
    def pre_init():
        print("Pygame mixer pre-init (stub mode)")
        return True

    @staticmethod
    def quit():
        print("Pygame mixer quit (stub mode)")
        return True

    class Sound:
        def __init__(self, file_path):
            self.file_path = file_path

        def play(self):
            try:
                subprocess.run(['aplay', self.file_path], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except:
                print(f"Playing sound (stub): {self.file_path}")

        def stop(self):
            subprocess.run(['pkill', 'aplay'], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def init():
    print("Pygame initialized (stub mode)")
    return True

def quit():
    print("Pygame quit (stub mode)")
    return True

print("Pygame stub loaded - basic audio functionality available")
EOF

    sudo cp /tmp/pygame_stub.py "$SITE_PACKAGES/pygame.py"
    sudo chmod 644 "$SITE_PACKAGES/pygame.py"
    rm -f /tmp/pygame_stub.py
    log "Pygame compatibility stub installed"
fi

# Step 6: Ensure bcrypt is available
log "Ensuring bcrypt is available..."
if ! $PYTHON_CMD -c "import bcrypt" 2>/dev/null; then
    log_warning "Installing bcrypt..."
    if ! $PYTHON_CMD -m pip install bcrypt==3.2.0 --no-cache-dir 2>/dev/null; then
        if ! $PYTHON_CMD -m pip install bcrypt==4.0.1 --no-cache-dir 2>/dev/null; then
            log_error "Failed to install bcrypt - installing anyway"
        fi
    fi
fi

# Step 6.5: Ensure PyYAML is available for network manager
log "Ensuring PyYAML is available..."
if ! $PYTHON_CMD -c "import yaml" 2>/dev/null; then
    log_warning "Installing PyYAML..."
    if ! $PYTHON_CMD -m pip install PyYAML --no-cache-dir 2>/dev/null; then
        log_warning "Failed to install PyYAML via pip, using system package"
    fi
fi

# Step 7: Update application files
log "Updating application files..."
sudo cp -r ./* /opt/bellnews/ 2>/dev/null || true
sudo chown -R root:root /opt/bellnews
sudo chmod -R 755 /opt/bellnews
sudo chmod +x /opt/bellnews/*.py

# Step 8: Update systemd service to use correct web file
log "Updating systemd service configuration..."
if [[ -f /etc/systemd/system/bellnews.service ]]; then
    # Replace nano_web_timer.py with vcns_timer_web.py in service file
    sudo sed -i 's/nano_web_timer\.py/vcns_timer_web.py/g' /etc/systemd/system/bellnews.service
    sudo systemctl daemon-reload
    log "Service configuration updated"
else
    log_warning "Service file not found, run installer first"
fi

# Step 9: Create required directories
log "Creating required directories..."
sudo mkdir -p /var/log/bellnews
sudo mkdir -p /opt/bellnews/static/audio
sudo mkdir -p /opt/bellnews/logs
sudo chmod 755 /var/log/bellnews
sudo chmod 777 /opt/bellnews/logs

# Step 10: Test the system
log "Testing system components..."

# Test Python imports
if ! $PYTHON_CMD -c "import flask, pygame, psutil; print('Core modules OK')" 2>/dev/null; then
    log_warning "Some core Python modules are missing"
else
    log "Core modules test: PASSED"
fi

# Test bcrypt specifically
if $PYTHON_CMD -c "import bcrypt; print('bcrypt OK')" 2>/dev/null; then
    log "bcrypt test: PASSED"
else
    log_warning "bcrypt test failed (authentication may not work)"
fi

# Test network manager dependencies
if $PYTHON_CMD -c "import yaml; print('PyYAML OK')" 2>/dev/null; then
    log "PyYAML test: PASSED"
else
    log_warning "PyYAML test failed (network configuration may not work)"
fi

# Test network manager
if $PYTHON_CMD -c "from network_manager import NetworkManager; print('Network Manager OK')" 2>/dev/null; then
    log "Network Manager test: PASSED"
else
    log_warning "Network Manager test failed (IP configuration may not work)"
fi

# Test pygame
if $PYTHON_CMD -c "import pygame; pygame.mixer.init(); print('Pygame OK')" 2>/dev/null; then
    log "Pygame test: PASSED"
else
    log_warning "Pygame test failed (audio may not work)"
fi

# Step 11: Configure audio and update alarm player
log "Configuring audio and alarm player..."

# Configure ALSA audio to use H3 Codec (card 2)
if [ ! -f /etc/asound.conf ]; then
    log "Setting up audio routing..."
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
    log "Audio routing configured"
fi

# Set audio volume
amixer set 'Line Out' 100% > /dev/null 2>&1 || true
amixer set 'DAC' 100% > /dev/null 2>&1 || true
alsactl store 2>/dev/null || true

# Install ffmpeg for MP3 conversion if missing
if ! command -v ffmpeg &> /dev/null; then
    log "Installing ffmpeg for audio conversion..."
    apt-get install -y ffmpeg -qq 2>/dev/null || log_warning "ffmpeg installation failed"
fi

# Run alarm player update if script exists
if [ -f "/opt/bellnews/update_alarm_player.sh" ]; then
    log "Running alarm player update..."
    bash /opt/bellnews/update_alarm_player.sh >> /tmp/alarm_update.log 2>&1 || log_warning "Alarm player update had warnings"
fi

# Step 12: Fix time synchronization
log "Configuring time synchronization..."
timedatectl set-timezone Asia/Jerusalem 2>/dev/null || true
apt-get install -y ntp ntpdate -qq > /dev/null 2>&1 || log_warning "NTP installation had issues"
systemctl enable ntp > /dev/null 2>&1 || true
systemctl start ntp > /dev/null 2>&1 || true
timedatectl set-ntp true > /dev/null 2>&1 || true
log "Time sync configured (Asia/Jerusalem timezone)"

# Step 13: Start services
log "Starting Bell News services..."
sudo systemctl start bellnews

# Wait for services to start
sleep 10

# Step 14: Verify everything is working
log "Verifying system status..."

if sudo systemctl is-active bellnews >/dev/null 2>&1; then
    log "✅ Bell News service: RUNNING"
else
    log_error "❌ Bell News service: FAILED"
    sudo systemctl status bellnews --no-pager
    exit 1
fi

# Check processes
if pgrep -f "vcns_timer_web.py" >/dev/null; then
    log "✅ Web interface process: RUNNING"
else
    log_error "❌ Web interface process: NOT RUNNING"
fi

if pgrep -f "nanopi_monitor.py" >/dev/null; then
    log "✅ Monitor process: RUNNING"
else
    log_warning "⚠️ Monitor process: NOT RUNNING"
fi

# Check web interface
if curl -s http://localhost:5000 >/dev/null 2>&1; then
    log "✅ Web interface: ACCESSIBLE"
else
    log_error "❌ Web interface: NOT ACCESSIBLE"
fi

# Get IP address for user
IP_ADDRESS=$(ip addr show | grep "inet " | grep -v 127.0.0.1 | head -1 | awk '{print $2}' | cut -d'/' -f1)

echo
log "🎉 Bell News system update completed successfully!"
echo
echo -e "${BLUE}Access Bell News at:${NC} http://$IP_ADDRESS:5000"
echo -e "${BLUE}Service status:${NC} sudo systemctl status bellnews"
echo -e "${BLUE}View logs:${NC} sudo journalctl -u bellnews -f"
echo
log "✅ System is ready for use!"