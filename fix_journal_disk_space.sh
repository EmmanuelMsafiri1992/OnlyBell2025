#!/bin/bash
# Fix Journal Disk Space Issue on NanoPi
# This script cleans up system journal logs that have filled up the disk

echo "=========================================="
echo "Journal Disk Space Fix for NanoPi"
echo "=========================================="
echo ""

# Check current journal disk usage
echo "Current journal disk usage:"
journalctl --disk-usage
echo ""

# Show current journal configuration
echo "Current journal configuration:"
if [ -f /etc/systemd/journald.conf ]; then
    grep -v "^#" /etc/systemd/journald.conf | grep -v "^$"
else
    echo "journald.conf not found or using defaults"
fi
echo ""

# Clean up old journal logs (keep only last 3 days)
echo "Cleaning up journal logs older than 3 days..."
journalctl --vacuum-time=3d
echo ""

# Limit journal size to 100MB
echo "Setting journal size limit to 100MB..."
journalctl --vacuum-size=100M
echo ""

# Configure journald to prevent future disk space issues
echo "Configuring journald settings..."

# Backup existing configuration
if [ -f /etc/systemd/journald.conf ]; then
    cp /etc/systemd/journald.conf /etc/systemd/journald.conf.backup.$(date +%Y%m%d_%H%M%S)
    echo "Backed up existing journald.conf"
fi

# Update journald configuration
cat > /etc/systemd/journald.conf <<'EOF'
#  This file is part of systemd.
#
#  systemd is free software; you can redistribute it and/or modify it
#  under the terms of the GNU Lesser General Public License as published by
#  the Free Software Foundation; either version 2.1 of the License, or
#  (at your option) any later version.
#
# Entries in this file show the compile time defaults.
# You can change settings by editing this file.
# Defaults can be restored by simply deleting this file.
#
# See journald.conf(5) for details.

[Journal]
Storage=persistent
Compress=yes
#Seal=yes
#SplitMode=uid
#SyncIntervalSec=5m
#RateLimitIntervalSec=30s
#RateLimitBurst=10000
SystemMaxUse=100M
SystemKeepFree=500M
SystemMaxFileSize=10M
SystemMaxFiles=10
#RuntimeMaxUse=
#RuntimeKeepFree=
#RuntimeMaxFileSize=
#RuntimeMaxFiles=100
MaxRetentionSec=3day
MaxFileSec=1day
#ForwardToSyslog=no
#ForwardToKMsg=no
#ForwardToConsole=no
#ForwardToWall=yes
#TTYPath=/dev/console
#MaxLevelStore=debug
#MaxLevelSyslog=debug
#MaxLevelKMsg=notice
#MaxLevelConsole=info
#MaxLevelWall=emerg
#LineMax=48K
#ReadKMsg=yes
EOF

echo "Updated journald.conf with:"
echo "  - SystemMaxUse=100M (maximum total disk space for journal)"
echo "  - SystemKeepFree=500M (keep this much disk space free)"
echo "  - SystemMaxFileSize=10M (max size per journal file)"
echo "  - SystemMaxFiles=10 (max number of journal files)"
echo "  - MaxRetentionSec=3day (keep logs for 3 days max)"
echo "  - MaxFileSec=1day (rotate daily)"
echo ""

# Restart systemd-journald to apply new configuration
echo "Restarting systemd-journald service..."
systemctl restart systemd-journald
echo ""

# Verify the changes
echo "Verifying journal disk usage after cleanup:"
journalctl --disk-usage
echo ""

# Show total disk usage
echo "Total disk usage:"
df -h /var/log/journal
echo ""

echo "=========================================="
echo "Journal disk space fix completed!"
echo "=========================================="
echo ""
echo "The system journal will now:"
echo "  1. Use maximum 100MB of disk space"
echo "  2. Keep logs for only 3 days"
echo "  3. Rotate logs daily"
echo "  4. Always keep 500MB free on the disk"
echo ""
echo "This should prevent future halting issues due to disk space."
