# Journal Disk Space Fix for NanoPi Halting Issue

## Problem Identified

The NanoPi is halting because the **system journal has filled up the disk**:

- **Current Usage**: 2.9GB of journal logs
- **Maximum Allowed**: 2.9GB (100% full)
- **Result**: System cannot write new logs and halts

This is shown in the journal logs:
```
System journal (/var/log/journal/) is currently using 2.9G.
Maximum allowed usage is set to 2.9G.
```

## Root Cause

The systemd journal was configured with default settings that allow it to consume too much disk space on the NanoPi's limited storage. Over time, logs accumulated and filled the allocated space, causing the system to halt when it couldn't write new log entries.

## Solution

Run the `fix_journal_disk_space.sh` script on the NanoPi:

```bash
# On the NanoPi, navigate to the application directory
cd /opt/bellnews

# Pull the latest changes
git pull

# Make the script executable
chmod +x fix_journal_disk_space.sh

# Run the fix script with root privileges
sudo ./fix_journal_disk_space.sh
```

## What the Fix Does

1. **Immediately cleans up old logs**:
   - Removes logs older than 3 days
   - Reduces total journal size to 100MB max

2. **Configures journald for the future**:
   - `SystemMaxUse=100M` - Maximum 100MB of disk space for all journals
   - `SystemKeepFree=500M` - Always keep 500MB free on disk
   - `SystemMaxFileSize=10M` - Each journal file limited to 10MB
   - `SystemMaxFiles=10` - Maximum 10 journal files
   - `MaxRetentionSec=3day` - Keep logs for 3 days only
   - `MaxFileSec=1day` - Rotate logs daily

3. **Prevents future halting**:
   - Journal will automatically delete old logs
   - System will always have adequate disk space
   - Logs are rotated and cleaned regularly

## Verification

After running the script, verify the fix worked:

```bash
# Check current journal disk usage (should be < 100MB)
journalctl --disk-usage

# Check overall disk space (should have plenty free)
df -h

# Check journald is running properly
systemctl status systemd-journald
```

## Long-term Monitoring

To prevent this from happening again, you can periodically check:

```bash
# Check journal size
journalctl --disk-usage

# View journald configuration
cat /etc/systemd/journald.conf | grep -v "^#" | grep -v "^$"
```

## Related Issues

This is a **different issue** from the previous memory leak fix (commit aa6aea0). That fix addressed:
- Memory accumulation in the alarm player
- Excessive file I/O from reloading alarms.json
- Pygame resource leaks

This new fix addresses:
- Disk space exhaustion from journal logs
- System halting due to inability to write logs
- Long-term log retention without cleanup

Both fixes are needed for stable operation.
