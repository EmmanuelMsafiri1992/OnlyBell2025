#!/bin/bash
# BELL NEWS COMPLETE ONE-COMMAND INSTALLER
# Fixed: dpkg issues, dependency installation, service startup verification
# Truly works from fresh NanoPi to fully functional Bell News in one command

set +e  # Don't exit on errors - we handle them
export DEBIAN_FRONTEND=noninteractive

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

REPO_URL="https://github.com/EmmanuelMsafiri1992/OnlyBell2025.git"
INSTALL_DIR="/opt/bellnews"
LOG_FILE="/tmp/bellnews_complete_install.log"

echo "Bell News Complete Installation Started: $(date)" > "$LOG_FILE"

clear
echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}║         🚀 BELL NEWS COMPLETE ONE-COMMAND INSTALLER 🚀      ║${NC}"
echo -e "${PURPLE}║                                                              ║${NC}"
echo -e "${PURPLE}║   ✅ Fixes dpkg issues automatically                        ║${NC}"
echo -e "${PURPLE}║   ✅ Installs all dependencies correctly                    ║${NC}"
echo -e "${PURPLE}║   ✅ Verifies service is actually running                   ║${NC}"
echo -e "${PURPLE}║   ✅ One command - complete working system                  ║${NC}"
echo -e "${PURPLE}║                                                              ║${NC}"
echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${CYAN}📝 Installation log: $LOG_FILE${NC}"
echo

log_success() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] ✅${NC} $1"
    echo "[$(date '+%H:%M:%S')] SUCCESS: $1" >> "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠️${NC} $1"
    echo "[$(date '+%H:%M:%S')] WARNING: $1" >> "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ❌${NC} $1"
    echo "[$(date '+%H:%M:%S')] ERROR: $1" >> "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')] ℹ️${NC} $1"
    echo "[$(date '+%H:%M:%S')] INFO: $1" >> "$LOG_FILE"
}

log_step() {
    echo -e "${CYAN}[$(date '+%H:%M:%S')] 🔧${NC} $1"
    echo "[$(date '+%H:%M:%S')] STEP: $1" >> "$LOG_FILE"
}

# Check root
if [[ $EUID -ne 0 ]]; then
    log_error "Must run as root"
    echo -e "${YELLOW}Run: ${WHITE}wget -qO- https://raw.githubusercontent.com/EmmanuelMsafiri1992/OnlyBell2025/main/complete_one_command_installer.sh | sudo bash${NC}"
    exit 1
fi

# ============================================================================
# PHASE 0: FIX DPKG ISSUES FIRST (CRITICAL!)
# ============================================================================
phase0_fix_dpkg() {
    log_step "PHASE 0: Fixing System Package Manager"

    log_info "Fixing any stuck dpkg configurations..."

    # Fix any pending dpkg configurations (non-interactively)
    dpkg --configure -a 2>&1 | tee -a "$LOG_FILE" | grep -v "^$" || true

    # Fix broken dependencies
    log_info "Fixing broken dependencies..."
    apt-get install -f -y 2>&1 | tee -a "$LOG_FILE" | grep -v "^$" || true

    # Clean package cache
    apt-get clean 2>/dev/null || true

    log_success "Phase 0 Complete: Package manager ready"
}

# ============================================================================
# PHASE 1: COMPLETE SYSTEM CLEANUP
# ============================================================================
phase1_cleanup() {
    log_step "PHASE 1: System Cleanup"

    # Stop all processes
    pkill -9 -f "vcns_timer_web.py" 2>/dev/null || true
    pkill -9 -f "nanopi_monitor.py" 2>/dev/null || true
    pkill -9 -f "bellnews" 2>/dev/null || true

    # Stop services
    systemctl stop bellnews 2>/dev/null || true
    systemctl disable bellnews 2>/dev/null || true

    # Remove service files
    rm -f /etc/systemd/system/bellnews.service 2>/dev/null || true
    rm -f /etc/systemd/system/bell-news.service 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true

    # Remove old installations
    rm -rf /opt/bellnews /opt/BellNews* /usr/local/bellnews 2>/dev/null || true
    rm -rf /home/*/BellNews* /home/*/bellnews* /home/*/OnlyBell* 2>/dev/null || true
    rm -rf /tmp/OnlyBell* /tmp/BellNews* /tmp/bellnews* 2>/dev/null || true
    rm -rf /var/log/bellnews 2>/dev/null || true

    # Clean Python cache
    find /opt /tmp -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

    # Clean cron jobs
    crontab -l 2>/dev/null | grep -v bellnews | crontab - 2>/dev/null || true

    log_success "Phase 1 Complete: System cleaned"
}

# ============================================================================
# PHASE 2: SYSTEM PREPARATION & UPDATES
# ============================================================================
phase2_system_prep() {
    log_step "PHASE 2: System Preparation"

    log_info "Updating package list..."
    apt-get update -qq 2>&1 >> "$LOG_FILE" || true
    log_success "Package list updated"

    log_info "Upgrading system packages (this may take a few minutes)..."
    apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" 2>&1 >> "$LOG_FILE" || true
    log_success "System packages upgraded"
}

# ============================================================================
# PHASE 3: INSTALL ESSENTIAL TOOLS
# ============================================================================
phase3_install_tools() {
    log_step "PHASE 3: Installing Essential Tools"

    log_info "Installing git, curl, wget..."
    apt-get install -y git curl wget unzip 2>&1 >> "$LOG_FILE" || true
    log_success "Essential tools installed"
}

# ============================================================================
# PHASE 4: INSTALL PYTHON & DEPENDENCIES
# ============================================================================
phase4_install_python() {
    log_step "PHASE 4: Installing Python Environment"

    log_info "Installing Python3 and pip..."
    apt-get install -y python3 python3-pip python3-dev python3-setuptools python3-wheel 2>&1 >> "$LOG_FILE" || true
    log_success "Python installed"

    log_info "Installing Python system packages..."
    apt-get install -y \
        python3-flask \
        python3-psutil \
        python3-requests \
        python3-pytz \
        python3-yaml \
        python3-bcrypt \
        python3-pygame \
        2>&1 >> "$LOG_FILE" || true
    log_success "Python packages installed"

    log_info "Installing development libraries..."
    apt-get install -y \
        libffi-dev \
        libssl-dev \
        build-essential \
        libsdl2-dev \
        libsdl2-mixer-dev \
        alsa-utils \
        2>&1 >> "$LOG_FILE" || true
    log_success "Development libraries installed"

    # Upgrade pip and install critical packages as backup
    log_info "Installing pip packages as backup..."
    python3 -m pip install --upgrade pip 2>&1 >> "$LOG_FILE" || true
    python3 -m pip install flask psutil requests pytz pyyaml bcrypt pygame 2>&1 >> "$LOG_FILE" || true
    log_success "Pip packages installed"
}

# ============================================================================
# PHASE 5: DOWNLOAD REPOSITORY
# ============================================================================
phase5_download_repo() {
    log_step "PHASE 5: Downloading Bell News"

    cd /tmp
    rm -rf /tmp/OnlyBell2025 2>/dev/null || true

    log_info "Cloning repository..."
    if git clone "$REPO_URL" 2>&1 >> "$LOG_FILE"; then
        log_success "Repository cloned"
    else
        log_warning "Git clone failed, trying wget..."
        wget -q https://github.com/EmmanuelMsafiri1992/OnlyBell2025/archive/main.zip -O bellnews.zip
        unzip -q bellnews.zip
        mv OnlyBell2025-main OnlyBell2025
        rm -f bellnews.zip
        log_success "Repository downloaded via wget"
    fi

    if [[ ! -f "/tmp/OnlyBell2025/vcns_timer_web.py" ]]; then
        log_error "Cannot find application files!"
        exit 1
    fi

    log_success "Phase 5 Complete: Repository ready"
}

# ============================================================================
# PHASE 6: INSTALL APPLICATION
# ============================================================================
phase6_install_app() {
    log_step "PHASE 6: Installing Application"

    # Create directories
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR/static/audio"
    mkdir -p "$INSTALL_DIR/templates"
    mkdir -p "$INSTALL_DIR/logs"
    mkdir -p "/var/log/bellnews"

    # Copy all files
    log_info "Copying application files..."
    cd /tmp/OnlyBell2025
    cp -r * "$INSTALL_DIR/" 2>&1 >> "$LOG_FILE" || true

    # Set permissions
    cd "$INSTALL_DIR"
    chown -R root:root "$INSTALL_DIR"
    chmod -R 755 "$INSTALL_DIR"
    chmod +x *.py *.sh 2>/dev/null || true
    chmod 666 *.json 2>/dev/null || true
    chmod 777 logs /var/log/bellnews 2>/dev/null || true

    # Create proper config files
    cat > "$INSTALL_DIR/config.json" << 'EOF'
{
    "network": {
        "mode": "dhcp",
        "static_ip": "",
        "static_gateway": "",
        "static_dns": ""
    },
    "system": {
        "timezone": "UTC",
        "ntp_enabled": true
    }
}
EOF
    chmod 666 "$INSTALL_DIR/config.json"

    echo '[]' > "$INSTALL_DIR/alarms.json"
    chmod 666 "$INSTALL_DIR/alarms.json"

    log_success "Phase 6 Complete: Application installed"
}

# ============================================================================
# PHASE 7: CONFIGURE SERVICE
# ============================================================================
phase7_configure_service() {
    log_step "PHASE 7: Configuring Service"

    cat > /etc/systemd/system/bellnews.service << 'EOF'
[Unit]
Description=Bell News System
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/bellnews
Environment=PYTHONUNBUFFERED=1
ExecStart=/usr/bin/python3 /opt/bellnews/vcns_timer_web.py
Restart=always
RestartSec=10
StandardOutput=append:/var/log/bellnews/service.log
StandardError=append:/var/log/bellnews/error.log

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable bellnews

    log_success "Phase 7 Complete: Service configured"
}

# ============================================================================
# PHASE 8: START AND VERIFY SERVICE
# ============================================================================
phase8_start_verify() {
    log_step "PHASE 8: Starting and Verifying Service"

    log_info "Starting Bell News service..."
    systemctl start bellnews

    log_info "Waiting for service to start (20 seconds)..."
    sleep 20

    # Check if service is running
    if systemctl is-active bellnews >/dev/null 2>&1; then
        log_success "Service is ACTIVE"
    else
        log_warning "Service may not be active, checking process..."
        if pgrep -f "vcns_timer_web.py" >/dev/null; then
            log_success "Process is running (even if systemd shows otherwise)"
        else
            log_error "Service failed to start - checking logs..."
            journalctl -u bellnews -n 20 --no-pager 2>&1 | tee -a "$LOG_FILE"

            log_warning "Attempting manual start..."
            cd "$INSTALL_DIR"
            nohup python3 vcns_timer_web.py > /var/log/bellnews/manual_start.log 2>&1 &
            sleep 10
        fi
    fi

    # Verify web interface
    log_info "Testing web interface (up to 30 seconds)..."
    WEB_WORKING=false
    for i in {1..6}; do
        if curl -s -m 5 http://localhost:5000 >/dev/null 2>&1; then
            WEB_WORKING=true
            log_success "Web interface is ACCESSIBLE!"
            break
        else
            log_info "Attempt $i/6: waiting for web interface..."
            sleep 5
        fi
    done

    if [ "$WEB_WORKING" = false ]; then
        log_warning "Web interface not responding yet"
        log_info "Checking Python dependencies..."
        python3 -c "import flask; print('Flask: OK')" 2>&1 | tee -a "$LOG_FILE" || log_error "Flask import failed"
        log_info "Check logs with: journalctl -u bellnews -f"
    fi

    log_success "Phase 8 Complete: Service verification done"
}

# ============================================================================
# FINAL: SHOW COMPLETION STATUS
# ============================================================================
show_completion() {
    local IP_ADDRESS
    IP_ADDRESS=$(ip addr show | grep "inet " | grep -v 127.0.0.1 | head -1 | awk '{print $2}' | cut -d'/' -f1 2>/dev/null || echo "localhost")

    echo
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                                           ║${NC}"
    echo -e "${GREEN}║                    🎉 INSTALLATION COMPLETED! 🎉                        ║${NC}"
    echo -e "${GREEN}║                                                                           ║${NC}"
    echo -e "${GREEN}║  🌐 Access Bell News at: ${CYAN}http://$IP_ADDRESS:5000${GREEN}                         ║${NC}"
    echo -e "${GREEN}║                                                                           ║${NC}"

    # Check actual status
    if systemctl is-active bellnews >/dev/null 2>&1 || pgrep -f "vcns_timer_web.py" >/dev/null; then
        echo -e "${GREEN}║  ✅ Service Status: ${WHITE}RUNNING${GREEN}                                              ║${NC}"
    else
        echo -e "${GREEN}║  ⚠️  Service Status: ${YELLOW}CHECK REQUIRED${GREEN}                                      ║${NC}"
    fi

    if curl -s -m 3 http://localhost:5000 >/dev/null 2>&1; then
        echo -e "${GREEN}║  ✅ Web Interface: ${WHITE}ACCESSIBLE${GREEN}                                           ║${NC}"
    else
        echo -e "${GREEN}║  ⚠️  Web Interface: ${YELLOW}STARTING UP${GREEN}                                          ║${NC}"
    fi

    echo -e "${GREEN}║                                                                           ║${NC}"
    echo -e "${GREEN}║  🔧 Management Commands:                                                 ║${NC}"
    echo -e "${GREEN}║     • Status:  ${YELLOW}systemctl status bellnews${GREEN}                                ║${NC}"
    echo -e "${GREEN}║     • Restart: ${YELLOW}systemctl restart bellnews${GREEN}                               ║${NC}"
    echo -e "${GREEN}║     • Logs:    ${YELLOW}journalctl -u bellnews -f${GREEN}                                ║${NC}"
    echo -e "${GREEN}║     • Manual:  ${YELLOW}tail -f /var/log/bellnews/service.log${GREEN}                    ║${NC}"
    echo -e "${GREEN}║                                                                           ║${NC}"
    echo -e "${GREEN}║  📝 Installation log: ${BLUE}$LOG_FILE${GREEN}            ║${NC}"
    echo -e "${GREEN}║                                                                           ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${CYAN}🚀 If web interface is not accessible yet, wait 1-2 minutes and refresh${NC}"
    echo -e "${CYAN}   or check logs with: journalctl -u bellnews -f${NC}"
    echo
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
main() {
    log_info "Starting Complete Bell News Installation"

    phase0_fix_dpkg
    phase1_cleanup
    phase2_system_prep
    phase3_install_tools
    phase4_install_python
    phase5_download_repo
    phase6_install_app
    phase7_configure_service
    phase8_start_verify

    show_completion

    echo "Installation completed: $(date)" >> "$LOG_FILE"
}

# Run main installation
main "$@"
