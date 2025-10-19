#!/bin/bash
# IMMEDIATE FIX for NanoPi - Run this now!
# This fixes the journal disk full issue that is causing halting

echo "=========================================="
echo "IMMEDIATE FIX - Cleaning Journal"
echo "=========================================="
echo ""

echo "Current journal usage:"
journalctl --disk-usage
echo ""

echo "Cleaning journal (keeping only last 3 days)..."
journalctl --vacuum-time=3d
echo ""

echo "Limiting journal to 100MB max..."
journalctl --vacuum-size=100M
echo ""

echo "New journal usage:"
journalctl --disk-usage
echo ""

echo "Fixing system time..."
systemctl stop ntp 2>/dev/null
ntpdate -s 216.239.35.0 || ntpdate -s 129.6.15.28 || ntpdate -s 132.163.96.1
systemctl start ntp 2>/dev/null
echo "Current time: $(date)"
echo ""

echo "Configuring journald permanently..."
# Backup existing config
cp /etc/systemd/journald.conf /etc/systemd/journald.conf.backup.$(date +%Y%m%d_%H%M%S)

# Update configuration
cat > /etc/systemd/journald.conf <<'EOF'
[Journal]
Storage=persistent
Compress=yes
SystemMaxUse=100M
SystemKeepFree=500M
SystemMaxFileSize=10M
SystemMaxFiles=10
MaxRetentionSec=3day
MaxFileSec=1day
EOF

echo "Restarting journald..."
systemctl restart systemd-journald
echo ""

echo "Checking disk space..."
df -h /
echo ""

echo "=========================================="
echo "FIX COMPLETE!"
echo "=========================================="
echo "Journal size: $(journalctl --disk-usage)"
echo "Current time: $(date)"
echo "Disk usage: $(df -h / | tail -1 | awk '{print $5}')"
echo ""
echo "The system will no longer halt due to journal disk space!"
