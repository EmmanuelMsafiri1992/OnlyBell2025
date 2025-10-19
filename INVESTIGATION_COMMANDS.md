# NanoPi Investigation Commands - Find Root Cause

Run these commands on the NanoPi to investigate what happened.

## 1. Check System Time and Uptime

```bash
# Current system time
date

# Check timezone and NTP status
timedatectl

# System uptime (when did it last reboot?)
uptime

# Last reboot time
who -b

# Boot history
last reboot | head -20
```

**What to look for:**
- Is the time correct or wrong?
- When was the last reboot?
- Was there an unexpected reboot?

---

## 2. Check System Logs for Errors

```bash
# View logs from current boot
journalctl -b 0 --no-pager

# View logs from previous boot (before the issue)
journalctl -b -1 --no-pager

# Show only errors and critical messages from previous boot
journalctl -b -1 -p err --no-pager

# Check for kernel panics or crashes
journalctl -b -1 | grep -i "panic\|crash\|fatal\|kill\|oom"

# Check for memory issues (Out Of Memory)
journalctl -b -1 | grep -i "oom\|out of memory\|killed process"

# Check for disk space issues
journalctl -b -1 | grep -i "no space\|disk full\|space left"

# Check systemd service failures
journalctl -b -1 | grep -i "failed\|error" | grep systemd
```

**What to look for:**
- "Out of memory" messages → Memory leak
- "No space left on device" → Disk full
- "segmentation fault" → Application crash
- Repeated errors → Service failing repeatedly

---

## 3. Check Journal Disk Usage

```bash
# Current journal disk usage
journalctl --disk-usage

# Total disk usage
df -h

# Check /var/log/journal specifically
du -sh /var/log/journal/*

# Find largest directories
du -h /var/log | sort -rh | head -20
```

**What to look for:**
- Journal using > 500MB → Too large, needs cleanup
- Disk > 90% full → Out of space issue
- `/var/log/journal` consuming GBs → Journal not rotating

---

## 4. Check Network Status

```bash
# Current IP address
ip addr show
hostname -I

# Network interface status
ip link show

# Default gateway
ip route

# DNS servers
cat /etc/resolv.conf

# Ping gateway
ping -c 3 $(ip route | grep default | awk '{print $3}')

# Ping internet
ping -c 3 8.8.8.8

# Test DNS resolution
nslookup google.com
```

**What to look for:**
- No IP address → Network didn't come up
- Different IP than expected → DHCP gave new IP
- Cannot ping gateway → Network cable/router issue
- Cannot ping internet → Router/ISP issue

---

## 5. Check SSH Service

```bash
# SSH service status
systemctl status ssh
systemctl status sshd

# Check if SSH is listening
netstat -tln | grep :22
# OR
ss -tln | grep :22

# Check SSH logs
journalctl -u ssh -b -1 --no-pager
journalctl -u sshd -b -1 --no-pager

# Check authentication logs
grep -i "ssh\|authentication" /var/log/auth.log | tail -50
```

**What to look for:**
- Service "inactive (dead)" → SSH didn't start
- "Connection refused" in logs → Firewall or config issue
- Multiple failed logins → Security issue

---

## 6. Check BellNews Services

```bash
# Find BellNews services
systemctl list-units | grep -i "bell\|timer\|alarm"

# Check web service status
systemctl status bellnews.service
systemctl status timer_web.service
systemctl status timerapp.service

# Check alarm player status
systemctl status alarm_player.service

# View BellNews logs from previous boot
journalctl -u bellnews.service -b -1 --no-pager
journalctl -u alarm_player.service -b -1 --no-pager

# Check application log files directly
tail -200 /opt/bellnews/logs/app.log
tail -200 /opt/bellnews/logs/alarm_player.log

# Check for errors in app logs
grep -i "error\|exception\|fatal" /opt/bellnews/logs/*.log | tail -50
```

**What to look for:**
- Service "failed" → Application crashed
- Memory errors → Memory leak
- Permission errors → File access issues
- Repeated restarts → Crash loop

---

## 7. Check Memory Usage History

```bash
# Current memory status
free -h

# Check for OOM (Out Of Memory) kills in previous boot
journalctl -b -1 | grep -i "out of memory\|oom killer\|killed process"

# Check which process was killed (if any)
dmesg | grep -i "killed process"

# System resource limits
ulimit -a
```

**What to look for:**
- "OOM killer" messages → System ran out of memory
- Process names that were killed → Which app caused issue
- Very low available memory → Memory leak

---

## 8. Check Time Sync Service

```bash
# Check if timesync-on-boot service exists
systemctl status timesync-on-boot.service

# Check if it ran on last boot
journalctl -u timesync-on-boot.service -b 0 --no-pager

# Check NTP service
systemctl status ntp
systemctl status systemd-timesyncd

# View time sync logs
journalctl -u ntp -b -1 --no-pager
journalctl -u timesync-on-boot -b -1 --no-pager
```

**What to look for:**
- Service "not found" → Time sync not installed
- Service "failed" → Network not ready, NTP servers unreachable
- "Name or service not known" → DNS issues

---

## 9. Check for System Crashes or Kernel Issues

```bash
# Check kernel messages
dmesg | tail -100

# Check for kernel panics
dmesg | grep -i "panic\|oops\|bug"

# Check system messages
tail -100 /var/log/syslog
# OR
tail -100 /var/log/messages

# Check for segmentation faults
journalctl -b -1 | grep -i "segfault\|segmentation fault"
```

**What to look for:**
- "Kernel panic" → System crash
- "segmentation fault" → Application crash
- Hardware errors → Device issues

---

## 10. Check Process and CPU Usage

```bash
# Current running processes
ps aux --sort=-%mem | head -20

# Check what was running before
journalctl -b -1 | grep -i "started\|stopped"

# Check for process crashes
journalctl -b -1 | grep -i "core dump\|segfault\|crashed"
```

**What to look for:**
- Processes using excessive memory → Memory leak
- Crashed processes → Application bugs

---

## 11. Check Last Shutdown Reason

```bash
# Check shutdown logs
journalctl --list-boots

# View shutdown sequence from previous boot
journalctl -b -1 -e | grep -i "shutdown\|reboot\|stopping"

# Check if shutdown was clean or forced
last -x | grep shutdown

# Check for unexpected reboots
last -x | grep reboot
```

**What to look for:**
- "Emergency Mode" → System couldn't boot properly
- No shutdown messages before reboot → Power loss or crash
- "watchdog" → System hung and was reset

---

## 12. Complete Investigation Script (Run All at Once)

```bash
#!/bin/bash
# Save this and run: sudo bash investigate.sh > investigation_report.txt

echo "============================================"
echo "NanoPi Investigation Report"
echo "Generated: $(date)"
echo "============================================"
echo ""

echo "=== 1. SYSTEM TIME ==="
date
echo ""
timedatectl
echo ""

echo "=== 2. UPTIME AND REBOOT HISTORY ==="
uptime
echo ""
who -b
echo ""
last reboot | head -10
echo ""

echo "=== 3. DISK USAGE ==="
df -h
echo ""
journalctl --disk-usage
echo ""

echo "=== 4. MEMORY USAGE ==="
free -h
echo ""

echo "=== 5. NETWORK STATUS ==="
ip addr show
echo ""
ip route
echo ""
cat /etc/resolv.conf
echo ""

echo "=== 6. CRITICAL ERRORS FROM PREVIOUS BOOT ==="
journalctl -b -1 -p err --no-pager | tail -50
echo ""

echo "=== 7. OOM (Out Of Memory) EVENTS ==="
journalctl -b -1 | grep -i "oom\|out of memory" | tail -20
echo ""

echo "=== 8. DISK SPACE ERRORS ==="
journalctl -b -1 | grep -i "no space\|disk full" | tail -20
echo ""

echo "=== 9. BELLNEWS SERVICE STATUS ==="
systemctl status bellnews.service 2>/dev/null || systemctl status timer_web.service 2>/dev/null
echo ""
systemctl status alarm_player.service 2>/dev/null
echo ""

echo "=== 10. SSH SERVICE STATUS ==="
systemctl status ssh 2>/dev/null || systemctl status sshd 2>/dev/null
echo ""

echo "=== 11. TIME SYNC SERVICE STATUS ==="
systemctl status timesync-on-boot.service 2>/dev/null
echo ""
systemctl status ntp 2>/dev/null
echo ""

echo "=== 12. LAST 30 LINES FROM BELLNEWS LOGS ==="
tail -30 /opt/bellnews/logs/app.log 2>/dev/null || echo "Log file not found"
echo ""
tail -30 /opt/bellnews/logs/alarm_player.log 2>/dev/null || echo "Log file not found"
echo ""

echo "=== 13. SHUTDOWN REASON ==="
journalctl -b -1 -e --no-pager | grep -i "shutdown\|reboot" | tail -10
echo ""

echo "============================================"
echo "Investigation Complete"
echo "============================================"
```

---

## How to Use These Commands

### Option 1: Run Individual Commands
Copy and paste each command to investigate specific areas.

### Option 2: Run Complete Investigation
```bash
# Create the investigation script
nano investigate.sh

# Paste the complete script from section 12 above

# Make it executable
chmod +x investigate.sh

# Run it and save output
sudo bash investigate.sh > investigation_report.txt

# View the report
less investigation_report.txt

# Or copy it to view elsewhere
cat investigation_report.txt
```

---

## What to Share for Diagnosis

After running the investigation, share these key outputs:

1. **Journal disk usage**: `journalctl --disk-usage`
2. **Errors from previous boot**: `journalctl -b -1 -p err --no-pager | tail -100`
3. **OOM events**: `journalctl -b -1 | grep -i "oom\|out of memory"`
4. **Disk space**: `df -h`
5. **Last reboot time**: `who -b` and `uptime`
6. **Complete investigation report**: `investigation_report.txt`

This will help identify if it was:
- **Memory issue** (OOM killer)
- **Disk space issue** (journal or logs filled up)
- **Application crash** (segmentation fault)
- **Network issue** (time sync failed)
- **Power issue** (unexpected reboot)

---

## Expected Results Based on Your Symptoms

Since you mentioned:
- Web interface still working (but wrong time)
- Cannot SSH in

**Most likely findings will be:**
1. **Time**: Wrong date (1984 or similar) because NTP sync failed
2. **Network**: Different IP address than expected
3. **SSH**: Service running but at different IP
4. **No OOM or crash**: System is actually running fine
5. **No disk full**: Probably adequate space
6. **Uptime**: Short (recently rebooted)

This points to **reboot + network change** rather than a crash or halt.
