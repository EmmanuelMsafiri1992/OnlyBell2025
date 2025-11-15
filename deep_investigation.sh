#!/bin/bash

################################################################################
# NanoPi Deep Investigation Script - Find Why It Still Halts Every 3 Days
#
# This script performs a comprehensive analysis to identify the root cause
# of the recurring halt issue that happens every 3 days.
#
# Usage: sudo bash deep_investigation.sh
#        The script will save a report to /tmp/deep_investigation_report.txt
################################################################################

set +e  # Don't exit on errors - we want to collect all data

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Report file
REPORT_FILE="/tmp/deep_investigation_report_$(date +%Y%m%d_%H%M%S).txt"

# Function to print and log
print_and_log() {
    echo -e "$1" | tee -a "$REPORT_FILE"
}

print_header() {
    local header="$1"
    print_and_log ""
    print_and_log "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    print_and_log "${CYAN} $header${NC}"
    print_and_log "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    print_and_log ""
}

print_success() {
    print_and_log "${GREEN}✓${NC} $1"
}

print_warning() {
    print_and_log "${YELLOW}⚠${NC} $1"
}

print_error() {
    print_and_log "${RED}✗${NC} $1"
}

print_info() {
    print_and_log "${BLUE}ℹ${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root: sudo bash deep_investigation.sh${NC}"
    exit 1
fi

# Banner
print_and_log "${PURPLE}"
cat << "EOF" | tee -a "$REPORT_FILE"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║     NanoPi Deep Investigation - 3-Day Halt Issue             ║
║     Finding the Root Cause                                   ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
print_and_log "${NC}"

print_info "Investigation started: $(date)"
print_info "Report will be saved to: $REPORT_FILE"
print_and_log ""

################################################################################
# 1. SYSTEM UPTIME AND REBOOT HISTORY
################################################################################
print_header "1. SYSTEM UPTIME AND REBOOT HISTORY"

print_info "Current system time:"
date | tee -a "$REPORT_FILE"
print_and_log ""

print_info "System uptime:"
uptime | tee -a "$REPORT_FILE"
UPTIME_DAYS=$(awk '{print int($1)}' /proc/uptime)
UPTIME_DAYS=$((UPTIME_DAYS / 86400))
print_and_log ""

if [ "$UPTIME_DAYS" -lt 3 ]; then
    print_error "System uptime is less than 3 days ($UPTIME_DAYS days) - likely rebooted recently"
    print_warning "This suggests the system IS experiencing regular reboots/halts"
else
    print_success "System uptime is $UPTIME_DAYS days - system has been stable"
fi
print_and_log ""

print_info "Last reboot time:"
who -b | tee -a "$REPORT_FILE"
print_and_log ""

print_info "Reboot history (last 20):"
last reboot | head -20 | tee -a "$REPORT_FILE"
print_and_log ""

################################################################################
# 2. CHECK FOR CRITICAL ERRORS IN LOGS
################################################################################
print_header "2. CRITICAL ERRORS FROM PREVIOUS BOOTS"

print_info "Checking for Out of Memory (OOM) events..."
OOM_COUNT=$(journalctl --since "30 days ago" | grep -i "out of memory\|oom killer\|killed process" | wc -l)
if [ "$OOM_COUNT" -gt 0 ]; then
    print_error "Found $OOM_COUNT OOM (Out of Memory) events in last 30 days!"
    print_and_log ""
    print_and_log "OOM Events:"
    journalctl --since "30 days ago" | grep -i "out of memory\|oom killer\|killed process" | tail -20 | tee -a "$REPORT_FILE"
    print_and_log ""
    print_error "THIS IS LIKELY THE CAUSE: System runs out of memory and kills processes"
else
    print_success "No OOM events found"
fi
print_and_log ""

print_info "Checking for disk space errors..."
DISK_ERRORS=$(journalctl --since "30 days ago" | grep -i "no space\|disk full\|enospc" | wc -l)
if [ "$DISK_ERRORS" -gt 0 ]; then
    print_error "Found $DISK_ERRORS disk space errors in last 30 days!"
    print_and_log ""
    print_and_log "Disk Space Errors:"
    journalctl --since "30 days ago" | grep -i "no space\|disk full\|enospc" | tail -20 | tee -a "$REPORT_FILE"
    print_and_log ""
    print_error "THIS IS LIKELY THE CAUSE: Disk fills up and system halts"
else
    print_success "No disk space errors found"
fi
print_and_log ""

print_info "Checking for application crashes..."
CRASH_COUNT=$(journalctl --since "30 days ago" | grep -i "segmentation fault\|core dump\|crashed" | wc -l)
if [ "$CRASH_COUNT" -gt 0 ]; then
    print_warning "Found $CRASH_COUNT application crashes in last 30 days"
    print_and_log ""
    print_and_log "Crash Events:"
    journalctl --since "30 days ago" | grep -i "segmentation fault\|core dump\|crashed" | tail -20 | tee -a "$REPORT_FILE"
    print_and_log ""
else
    print_success "No application crashes found"
fi
print_and_log ""

print_info "Checking for kernel panics..."
PANIC_COUNT=$(journalctl --since "30 days ago" | grep -i "kernel panic\|oops" | wc -l)
if [ "$PANIC_COUNT" -gt 0 ]; then
    print_error "Found $PANIC_COUNT kernel panics!"
    journalctl --since "30 days ago" | grep -i "kernel panic\|oops" | tail -20 | tee -a "$REPORT_FILE"
else
    print_success "No kernel panics found"
fi
print_and_log ""

print_info "Checking for watchdog resets..."
WATCHDOG_COUNT=$(journalctl --since "30 days ago" | grep -i "watchdog" | wc -l)
if [ "$WATCHDOG_COUNT" -gt 0 ]; then
    print_warning "Found $WATCHDOG_COUNT watchdog events (system hung and was reset)"
    journalctl --since "30 days ago" | grep -i "watchdog" | tail -20 | tee -a "$REPORT_FILE"
    print_and_log ""
else
    print_success "No watchdog resets found"
fi
print_and_log ""

################################################################################
# 3. MEMORY ANALYSIS
################################################################################
print_header "3. MEMORY USAGE ANALYSIS"

print_info "Current memory usage:"
free -h | tee -a "$REPORT_FILE"
print_and_log ""

AVAILABLE_MB=$(free -m | awk 'NR==2 {print $7}')
TOTAL_MB=$(free -m | awk 'NR==2 {print $2}')
USED_PERCENT=$((100 - (AVAILABLE_MB * 100 / TOTAL_MB)))

print_info "Memory usage: ${USED_PERCENT}% (${AVAILABLE_MB}MB available out of ${TOTAL_MB}MB)"
if [ "$AVAILABLE_MB" -lt 50 ]; then
    print_error "Very low available memory! Memory leak suspected!"
elif [ "$AVAILABLE_MB" -lt 100 ]; then
    print_warning "Low available memory - monitor for leaks"
else
    print_success "Available memory is adequate"
fi
print_and_log ""

print_info "Top memory-consuming processes:"
ps aux --sort=-%mem | head -10 | tee -a "$REPORT_FILE"
print_and_log ""

print_info "Checking for memory leak patterns (Python processes):"
PYTHON_MEM=$(ps aux | grep python | grep -v grep | awk '{sum+=$6} END {print sum/1024}')
if [ -n "$PYTHON_MEM" ]; then
    PYTHON_MEM_INT=$(echo "$PYTHON_MEM" | awk '{print int($1)}')
    print_info "Total Python processes memory: ${PYTHON_MEM_INT}MB"
    if [ "$PYTHON_MEM_INT" -gt 300 ]; then
        print_error "Python processes using excessive memory (>300MB) - MEMORY LEAK SUSPECTED!"
    elif [ "$PYTHON_MEM_INT" -gt 150 ]; then
        print_warning "Python processes using significant memory (>150MB)"
    else
        print_success "Python memory usage is normal"
    fi
else
    print_info "No Python processes found running"
fi
print_and_log ""

################################################################################
# 4. DISK SPACE ANALYSIS
################################################################################
print_header "4. DISK SPACE ANALYSIS"

print_info "Current disk usage:"
df -h | tee -a "$REPORT_FILE"
print_and_log ""

ROOT_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$ROOT_USAGE" -gt 90 ]; then
    print_error "Disk usage critically high: ${ROOT_USAGE}%"
elif [ "$ROOT_USAGE" -gt 80 ]; then
    print_warning "Disk usage high: ${ROOT_USAGE}%"
else
    print_success "Disk usage acceptable: ${ROOT_USAGE}%"
fi
print_and_log ""

print_info "Journal disk usage:"
journalctl --disk-usage | tee -a "$REPORT_FILE"
print_and_log ""

JOURNAL_MB=$(journalctl --disk-usage 2>&1 | grep -oP '\d+\.\d+M|\d+\.\d+G' | head -1)
print_info "Journal size: $JOURNAL_MB"
if [[ "$JOURNAL_MB" == *"G"* ]]; then
    print_error "Journal using gigabytes of space! This should be limited to 100MB!"
    print_error "THIS IS LIKELY THE CAUSE: Journal fills disk and causes halt"
elif [[ "$JOURNAL_MB" == *"M"* ]]; then
    JOURNAL_SIZE=$(echo "$JOURNAL_MB" | sed 's/M//')
    JOURNAL_SIZE_INT=$(echo "$JOURNAL_SIZE" | awk '{print int($1)}')
    if [ "$JOURNAL_SIZE_INT" -gt 500 ]; then
        print_warning "Journal larger than expected (should be ~100MB)"
    else
        print_success "Journal size is within limits"
    fi
fi
print_and_log ""

print_info "Largest directories in /var:"
du -h /var 2>/dev/null | sort -rh | head -15 | tee -a "$REPORT_FILE"
print_and_log ""

print_info "Checking for large log files:"
find /var/log -type f -size +50M 2>/dev/null | xargs ls -lh 2>/dev/null | tee -a "$REPORT_FILE"
print_and_log ""

################################################################################
# 5. BELLNEWS SERVICE ANALYSIS
################################################################################
print_header "5. BELLNEWS SERVICES ANALYSIS"

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
    print_error "Cannot find BellNews installation"
    INSTALL_DIR="/opt/bellnews"  # Assume default for rest of checks
fi
print_and_log ""

# Find web service
WEB_SERVICE=""
for svc in bellnews.service timer_web.service timerapp.service; do
    if systemctl list-unit-files | grep -q "$svc"; then
        WEB_SERVICE=$svc
        break
    fi
done

if [ -n "$WEB_SERVICE" ]; then
    print_info "Web service: $WEB_SERVICE"
    systemctl status "$WEB_SERVICE" --no-pager | tee -a "$REPORT_FILE"
    print_and_log ""

    # Check restart count
    RESTART_COUNT=$(journalctl -u "$WEB_SERVICE" --since "30 days ago" | grep -i "started\|restarted" | wc -l)
    print_info "Web service restarts in last 30 days: $RESTART_COUNT"
    if [ "$RESTART_COUNT" -gt 50 ]; then
        print_warning "Service restarting frequently - may indicate crashes"
    fi
    print_and_log ""
else
    print_warning "Web service not found"
fi
print_and_log ""

# Check alarm player service
if systemctl list-unit-files | grep -q "alarm_player.service"; then
    print_info "Alarm player service status:"
    systemctl status alarm_player.service --no-pager | tee -a "$REPORT_FILE"
    print_and_log ""

    ALARM_RESTART_COUNT=$(journalctl -u alarm_player.service --since "30 days ago" | grep -i "started\|restarted" | wc -l)
    print_info "Alarm service restarts in last 30 days: $ALARM_RESTART_COUNT"
    if [ "$ALARM_RESTART_COUNT" -gt 50 ]; then
        print_warning "Alarm service restarting frequently - may indicate crashes"
    fi
else
    print_info "Alarm player service not found or not installed"
fi
print_and_log ""

# Check application logs
if [ -d "$INSTALL_DIR/logs" ]; then
    print_info "Application log files:"
    ls -lh "$INSTALL_DIR/logs/" | tee -a "$REPORT_FILE"
    print_and_log ""

    print_info "Checking for large log files in application:"
    find "$INSTALL_DIR/logs" -type f -size +10M 2>/dev/null | xargs ls -lh 2>/dev/null | tee -a "$REPORT_FILE"
    print_and_log ""

    print_info "Recent errors in application logs:"
    grep -r "ERROR\|CRITICAL\|Exception" "$INSTALL_DIR/logs/" 2>/dev/null | tail -20 | tee -a "$REPORT_FILE"
    print_and_log ""
fi

################################################################################
# 6. CHECK FOR CRON JOBS AND SCHEDULED TASKS
################################################################################
print_header "6. SCHEDULED TASKS AND CRON JOBS"

print_info "System-wide cron jobs:"
cat /etc/crontab 2>/dev/null | grep -v "^#" | tee -a "$REPORT_FILE"
print_and_log ""

print_info "Cron jobs in /etc/cron.d/:"
ls -la /etc/cron.d/ 2>/dev/null | tee -a "$REPORT_FILE"
for f in /etc/cron.d/*; do
    if [ -f "$f" ]; then
        print_and_log "--- Content of $f ---"
        cat "$f" | grep -v "^#" | tee -a "$REPORT_FILE"
        print_and_log ""
    fi
done

print_info "Root user crontab:"
crontab -l 2>/dev/null | grep -v "^#" | tee -a "$REPORT_FILE" || print_info "No root crontab"
print_and_log ""

print_info "Systemd timers:"
systemctl list-timers --all --no-pager | tee -a "$REPORT_FILE"
print_and_log ""

################################################################################
# 7. CHECK JOURNAL CONFIGURATION
################################################################################
print_header "7. JOURNAL CONFIGURATION"

print_info "Current journald configuration:"
if [ -f /etc/systemd/journald.conf ]; then
    cat /etc/systemd/journald.conf | grep -v "^#" | grep -v "^$" | tee -a "$REPORT_FILE"
    print_and_log ""

    # Verify limits are set
    if grep -q "SystemMaxUse=100M" /etc/systemd/journald.conf; then
        print_success "Journal size limit is configured (100MB)"
    else
        print_error "Journal size limit NOT configured - journal can grow unlimited!"
        print_error "THIS IS LIKELY THE CAUSE: Journal grows and fills disk"
    fi

    if grep -q "MaxRetentionSec" /etc/systemd/journald.conf; then
        print_success "Journal retention is configured"
    else
        print_warning "Journal retention not configured - old logs may accumulate"
    fi
else
    print_error "journald.conf not found - journal may have no limits!"
fi
print_and_log ""

################################################################################
# 8. CHECK FOR TEMPERATURE/HARDWARE ISSUES
################################################################################
print_header "8. HARDWARE AND TEMPERATURE"

print_info "CPU temperature:"
TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
if [ -n "$TEMP" ]; then
    TEMP_C=$((TEMP / 1000))
    print_info "Current CPU temperature: ${TEMP_C}°C"
    if [ "$TEMP_C" -gt 80 ]; then
        print_error "CPU temperature is very high! Overheating may cause instability"
    elif [ "$TEMP_C" -gt 70 ]; then
        print_warning "CPU temperature is elevated"
    else
        print_success "CPU temperature is normal"
    fi
else
    print_info "Temperature sensor not available"
fi
print_and_log ""

print_info "CPU frequency and throttling:"
cat /sys/devices/system/cpu/cpu*/cpufreq/cpuinfo_cur_freq 2>/dev/null | tee -a "$REPORT_FILE"
print_and_log ""

################################################################################
# 9. CHECK NETWORK AND TIME SYNC
################################################################################
print_header "9. NETWORK AND TIME SYNCHRONIZATION"

print_info "Current IP address:"
hostname -I | tee -a "$REPORT_FILE"
print_and_log ""

print_info "Network interfaces:"
ip addr show | tee -a "$REPORT_FILE"
print_and_log ""

print_info "Time synchronization status:"
timedatectl | tee -a "$REPORT_FILE"
print_and_log ""

print_info "NTP service status:"
systemctl status ntp --no-pager 2>/dev/null | tee -a "$REPORT_FILE" || print_info "NTP service not found"
print_and_log ""

print_info "Boot-time timesync service:"
systemctl status timesync-on-boot.service --no-pager 2>/dev/null | tee -a "$REPORT_FILE" || print_warning "timesync-on-boot service not found"
print_and_log ""

################################################################################
# 10. CHECK FOR FILE HANDLE LEAKS
################################################################################
print_header "10. FILE HANDLES AND SYSTEM RESOURCES"

print_info "Current file handle usage:"
print_and_log "File handles used: $(cat /proc/sys/fs/file-nr | awk '{print $1}')"
print_and_log "File handles max:  $(cat /proc/sys/fs/file-nr | awk '{print $3}')"
print_and_log ""

print_info "Processes with most open files:"
lsof 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -rn | head -10 | tee -a "$REPORT_FILE"
print_and_log ""

print_info "System resource limits:"
ulimit -a | tee -a "$REPORT_FILE"
print_and_log ""

################################################################################
# 11. SUSPICIOUS PATTERNS IN LOGS
################################################################################
print_header "11. SUSPICIOUS PATTERNS IN SYSTEM LOGS"

print_info "Checking for repeated error patterns..."
journalctl --since "7 days ago" -p err --no-pager | tail -50 | tee -a "$REPORT_FILE"
print_and_log ""

print_info "Checking for service failures..."
journalctl --since "7 days ago" | grep -i "failed\|error" | grep systemd | tail -30 | tee -a "$REPORT_FILE"
print_and_log ""

################################################################################
# 12. SUMMARY AND RECOMMENDATIONS
################################################################################
print_header "12. SUMMARY AND LIKELY CAUSES"

print_and_log "${YELLOW}Based on the investigation, here are the most likely causes:${NC}"
print_and_log ""

# Determine likely causes
LIKELY_CAUSES=()

if [ "$OOM_COUNT" -gt 0 ]; then
    LIKELY_CAUSES+=("${RED}1. MEMORY LEAK - System runs out of memory (found $OOM_COUNT OOM events)${NC}")
fi

if [ "$DISK_ERRORS" -gt 0 ]; then
    LIKELY_CAUSES+=("${RED}2. DISK FULL - Disk fills up and system halts (found $DISK_ERRORS errors)${NC}")
fi

if [[ "$JOURNAL_MB" == *"G"* ]]; then
    LIKELY_CAUSES+=("${RED}3. JOURNAL NOT LIMITED - Journal grows unlimited and fills disk${NC}")
fi

if [ "$AVAILABLE_MB" -lt 100 ]; then
    LIKELY_CAUSES+=("${YELLOW}4. LOW MEMORY - Currently low on available memory (${AVAILABLE_MB}MB)${NC}")
fi

if [ "$ROOT_USAGE" -gt 85 ]; then
    LIKELY_CAUSES+=("${YELLOW}5. HIGH DISK USAGE - Disk is ${ROOT_USAGE}% full${NC}")
fi

if [ "$UPTIME_DAYS" -lt 3 ]; then
    LIKELY_CAUSES+=("${YELLOW}6. RECENT REBOOT - System rebooted recently (uptime: $UPTIME_DAYS days)${NC}")
fi

if [ ${#LIKELY_CAUSES[@]} -eq 0 ]; then
    print_success "No obvious problems detected in current state"
    print_info "System may have been fixed by previous scripts, or issue is intermittent"
else
    for cause in "${LIKELY_CAUSES[@]}"; do
        print_and_log "$cause"
    done
fi

print_and_log ""
print_and_log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
print_and_log ""

print_info "Complete investigation report saved to: $REPORT_FILE"
print_and_log ""

print_and_log "${GREEN}Next Steps:${NC}"
print_and_log "1. Review the report above for errors and warnings"
print_and_log "2. Focus on issues marked with ✗ (errors) and ⚠ (warnings)"
print_and_log "3. If journal is not limited, run: sudo bash fix_all_halt_issues.sh"
print_and_log "4. If memory leaks detected, check alarm_player.py is latest version"
print_and_log "5. Monitor system for 3 days and check: journalctl -b -1 -p err"
print_and_log ""

print_success "Investigation completed: $(date)"
