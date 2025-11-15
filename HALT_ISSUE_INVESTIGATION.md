# NanoPi 3-Day Halt Issue - Deep Investigation Guide

## Problem Summary

Your NanoPi halts **every 3 days** despite running multiple fix scripts. This document will help you identify the root cause and fix it permanently.

## Previous Fixes Applied (But Issue Persists)

✓ Journal disk space limit (100MB)
✓ Memory leak fixes in alarm_player.py
✓ Time synchronization service
✓ Network auto-start (DHCP)

**Since the problem persists, there's another underlying cause.**

---

## Most Likely Causes (Based on Pattern Analysis)

### 1. **Journal Limits Not Actually Applied** ⚠️ MOST LIKELY
Even though the fix script was run, the journal configuration may not have persisted:
- systemd-journald might not have restarted properly
- Configuration file might have been overwritten
- Limits may not be enforced correctly

**Every 3 days pattern suggests**: Logs accumulate → disk fills → system halts

### 2. **Application Log Files Growing Unchecked**
The fix scripts limit the system journal, but NOT application logs:
- `/opt/bellnews/logs/*.log` files may grow unlimited
- Python application might not rotate logs
- Over 3 days, logs could fill gigabytes

### 3. **Memory Leak Still Present**
If the code wasn't updated properly:
- Memory grows slowly over time
- After ~3 days, RAM exhausted
- OOM (Out of Memory) killer terminates processes
- System becomes unstable

### 4. **Cron Job or Scheduled Task**
A scheduled task might be:
- Running every 3 days and causing issues
- Cleaning logs incorrectly (deleting critical files)
- Rebooting the system intentionally

### 5. **Python Process Not Garbage Collecting**
Even with gc.collect() in code:
- References might not be released properly
- Pygame audio cache could accumulate
- File handles might leak

---

## Step-by-Step Investigation Process

### **STEP 1: Run the Deep Investigation Script on Your NanoPi**

Since you're already logged into the NanoPi at `/opt/bellnews`, run these commands:

```bash
# Make sure you're in the bellnews directory
cd /opt/bellnews

# Make the script executable
chmod +x deep_investigation.sh

# Run the investigation (as root)
sudo bash deep_investigation.sh
```

The script will:
- Check system logs for OOM events
- Verify journal configuration is actually applied
- Check disk space and memory usage
- Analyze application logs
- Look for cron jobs
- Check for file handle leaks
- Generate a comprehensive report

**Output**: The script saves a detailed report to `/tmp/deep_investigation_report_[timestamp].txt`

### **STEP 2: Review the Report**

After running the script, look for these critical indicators:

```bash
# View the report
cat /tmp/deep_investigation_report_*.txt | less

# Look for specific issues:
```

**What to look for:**

1. **"Found X OOM events"** → Memory leak is the cause
2. **"Journal using gigabytes"** → Journal limits not working
3. **"Disk usage critically high"** → Something filling disk
4. **"Python processes using excessive memory"** → Application memory leak
5. **"Service restarting frequently"** → Application crashing repeatedly

### **STEP 3: Run Additional Diagnostic Commands**

Based on my analysis, run these commands on your NanoPi to get more specific data:

#### A. Check if Journal Limits Are Actually Enforced

```bash
# Check current journal size
journalctl --disk-usage

# Check journald configuration
cat /etc/systemd/journald.conf | grep -v "^#" | grep -v "^$"

# Verify limits are set correctly
grep SystemMaxUse /etc/systemd/journald.conf
grep MaxRetentionSec /etc/systemd/journald.conf
```

**Expected**: Journal should be < 200MB and configuration should show `SystemMaxUse=100M`

**If not**: Journal limits were never applied or were reset

#### B. Check Application Log Sizes

```bash
# Check size of application logs
ls -lh /opt/bellnews/logs/

# Check total size
du -sh /opt/bellnews/logs/

# Find if any log files are huge
find /opt/bellnews/logs -type f -size +50M -ls
```

**Expected**: Logs should be small (< 50MB total)

**If huge**: Application logs are filling disk

#### C. Check Memory Usage Over Time

```bash
# Current memory
free -h

# Check which processes are using memory
ps aux --sort=-%mem | head -15

# Check for Python memory specifically
ps aux | grep python | awk '{sum+=$6} END {print "Total Python Memory: " sum/1024 " MB"}'
```

**Expected**: Python processes should use < 150MB total

**If > 300MB**: Memory leak in application

#### D. Check for OOM Events in History

```bash
# Check last 30 days for Out of Memory events
journalctl --since "30 days ago" | grep -i "out of memory\|oom killer"

# Check if any processes were killed
journalctl --since "30 days ago" | grep -i "killed process"

# Check system messages for memory issues
dmesg | grep -i "out of memory"
```

**If found**: OOM killer is terminating processes when memory runs out

#### E. Check Uptime Pattern

```bash
# Current uptime
uptime

# Uptime in days
awk '{print "Uptime: " int($1/86400) " days"}' /proc/uptime

# Last 10 reboot times
last reboot | head -10
```

**Check the pattern**: Are reboots happening every ~3 days?

---

## Most Likely Scenarios and Solutions

### **Scenario 1: Journal Still Growing Unlimited** (70% probability)

**Symptoms:**
- `journalctl --disk-usage` shows > 500MB
- Configuration file shows limits but journal is still large
- Disk usage grows over 3 days then fills up

**Root Cause:**
The journal limits were set in config but `systemd-journald` wasn't restarted, or there's a permission issue.

**Fix:**
```bash
# Apply journal limits forcefully
sudo journalctl --vacuum-size=100M
sudo journalctl --vacuum-time=3d

# Verify config
sudo nano /etc/systemd/journald.conf

# Make sure these lines exist (not commented):
SystemMaxUse=100M
MaxRetentionSec=3day

# Restart journald service
sudo systemctl restart systemd-journald

# Verify it worked
journalctl --disk-usage
```

### **Scenario 2: Application Logs Growing Unlimited** (60% probability)

**Symptoms:**
- `/opt/bellnews/logs/` directory is huge (> 500MB)
- Individual log files are > 100MB
- System journal is fine, but disk still fills

**Root Cause:**
Python application doesn't rotate logs, or logging is too verbose.

**Fix:**
```bash
# Check current log sizes
ls -lh /opt/bellnews/logs/

# Clean old logs
cd /opt/bellnews/logs
sudo rm -f *.log.* *.log.[0-9]*

# If logs are huge, truncate them (DON'T DELETE - service might fail)
sudo truncate -s 0 /opt/bellnews/logs/*.log

# Set up log rotation
sudo nano /etc/logrotate.d/bellnews
```

Add this content:
```
/opt/bellnews/logs/*.log {
    daily
    rotate 3
    maxsize 10M
    missingok
    notifempty
    compress
    delaycompress
    create 0644 root root
}
```

Then test:
```bash
sudo logrotate -f /etc/logrotate.d/bellnews
```

### **Scenario 3: Memory Leak in Application** (40% probability)

**Symptoms:**
- `ps aux` shows Python using > 300MB
- Memory usage grows over time
- `journalctl` shows OOM killer events
- System becomes sluggish before halt

**Root Cause:**
Code wasn't updated properly, or there's still a leak in alarm_player.py

**Fix:**
```bash
cd /opt/bellnews

# Update to absolute latest code
git fetch origin main
git reset --hard origin/main

# Verify memory leak fixes are present
grep -n "gc.collect()" alarm_player.py
grep -n "should_reload_alarms" alarm_player.py
grep -n "pygame.mixer.music.unload()" alarm_player.py

# If any are missing, the code is outdated

# Restart services with new code
sudo systemctl restart bellnews.service
sudo systemctl restart alarm_player.service

# Monitor memory usage
watch -n 5 'ps aux | grep python | grep -v grep'
```

### **Scenario 4: Cron Job Causing Issues** (20% probability)

**Symptoms:**
- Exact 3-day intervals between halts
- Logs show scheduled tasks running
- System activity spikes every 3 days

**Root Cause:**
A cron job or systemd timer runs every 3 days and causes problems.

**Fix:**
```bash
# Check all cron jobs
crontab -l
cat /etc/crontab
ls -la /etc/cron.d/

# Check systemd timers
systemctl list-timers --all

# Look for anything with "3 day" or "72 hour" intervals
grep -r "3" /etc/cron.d/
```

If found, disable it:
```bash
sudo systemctl disable suspicious-timer.timer
# OR
sudo crontab -e  # and comment out the line
```

---

## What To Send Me After Investigation

After running the deep investigation script and the additional commands above, please provide:

### **1. Investigation Report**
```bash
cat /tmp/deep_investigation_report_*.txt
```

### **2. Journal Size**
```bash
journalctl --disk-usage
```

### **3. Application Log Sizes**
```bash
ls -lh /opt/bellnews/logs/
du -sh /opt/bellnews/logs/
```

### **4. Memory Usage**
```bash
free -h
ps aux --sort=-%mem | head -15
```

### **5. Uptime and Reboot Pattern**
```bash
uptime
awk '{print "Uptime: " int($1/86400) " days"}' /proc/uptime
last reboot | head -10
```

### **6. OOM Events (if any)**
```bash
journalctl --since "30 days ago" | grep -i "out of memory\|oom killer" | wc -l
```

### **7. Disk Usage**
```bash
df -h
```

With this information, I can pinpoint the exact cause and provide a permanent fix.

---

## Quick Commands to Copy-Paste on NanoPi

If you want to run everything at once, copy this entire block:

```bash
echo "=== NANOPI HALT INVESTIGATION ==="
echo ""
echo "1. Journal Size:"
journalctl --disk-usage
echo ""
echo "2. Disk Usage:"
df -h
echo ""
echo "3. Memory Usage:"
free -h
echo ""
echo "4. Python Memory:"
ps aux | grep python | awk '{sum+=$6} END {print "Total: " sum/1024 " MB"}'
echo ""
echo "5. Application Logs:"
ls -lh /opt/bellnews/logs/
echo ""
echo "6. Uptime:"
uptime
awk '{print "Days: " int($1/86400)}' /proc/uptime
echo ""
echo "7. OOM Events in Last 30 Days:"
journalctl --since "30 days ago" | grep -i "out of memory\|oom killer" | wc -l
echo ""
echo "8. Last 10 Reboots:"
last reboot | head -10
echo ""
echo "9. Journal Config:"
cat /etc/systemd/journald.conf | grep -v "^#" | grep -v "^$"
echo ""
echo "=== END OF INVESTIGATION ==="
```

---

## Expected Timeline

1. **Now**: Run deep_investigation.sh and collect data (5 minutes)
2. **Then**: Share the results so I can analyze (immediate)
3. **Next**: Apply the specific fix based on findings (10 minutes)
4. **Wait**: Monitor for 3 days to confirm fix worked
5. **Verify**: Check system is still running after 4+ days

---

## Prevention After Fix

Once we identify and fix the root cause, I'll help you set up:

1. **Monitoring script** - Alerts before disk/memory fills
2. **Automatic log rotation** - Prevents logs from growing
3. **Health check cron** - Daily verification system is healthy
4. **Resource limits** - Hard limits on memory and disk usage

---

## Notes

- The 3-day pattern is very specific, suggesting a resource accumulation issue
- Most likely: Either logs (journal or application) or memory leak
- The fix scripts may have run but not persisted through reboot
- This is solvable - we just need the diagnostic data to confirm the exact cause

Run the investigation now and share the results. We'll get this fixed permanently! 🔧
