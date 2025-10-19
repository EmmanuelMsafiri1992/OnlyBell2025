# NanoPi Connectivity Issues - Diagnosis and Solutions

## Problem Description

You experienced:
1. **Wrong time and date** - System clock reset
2. **SSH access lost** - Cannot connect via PuTTY
3. **Web interface still working** - Application running but with wrong time

This is **different from the previous halting issue** (which was caused by memory leaks and journal disk space).

## Root Causes

### 1. Time Reset Issue
**Why it happens:**
- NanoPi NEO has **no RTC (Real-Time Clock) battery**
- On reboot, clock resets to 1984 or similar default date
- System needs NTP sync after network comes up
- If network isn't ready or time sync fails, time stays wrong

**Impact:**
- Alarms trigger at wrong times or not at all
- Log timestamps are incorrect
- Web interface shows wrong time

### 2. SSH Connectivity Loss
**Possible causes:**
- **Network configuration changed** - Static IP may have changed to DHCP or vice versa
- **IP address conflict** - Another device took the same IP
- **Network service failed** - eth0 didn't come up after reboot
- **Router DHCP lease expired** - NanoPi got a different IP
- **SSH service crashed** - sshd not running

**Impact:**
- Cannot connect via PuTTY on expected IP address
- Remote management unavailable
- Must use physical access (monitor/keyboard) to diagnose

## Solutions

### Immediate Fix (Physical Access Required)

If you can't SSH in, you need physical access to the NanoPi:

1. **Connect monitor and keyboard** to NanoPi
2. **Login as root** (or your user account)
3. **Run the diagnostic script:**

```bash
cd /opt/bellnews
sudo bash diagnose_and_fix_connectivity.sh
```

This script will:
- Check and fix system time
- Verify network connectivity
- Check SSH service status
- Clean up disk space if needed
- Restart failed services
- Show you current IP address

### Finding the New IP Address

If the IP changed, you need to find it:

```bash
# Method 1: Check on the NanoPi directly
ip addr show
ip addr show eth0 | grep "inet "

# Method 2: Check your router's DHCP client list
# Login to router admin panel (usually 192.168.1.1)
# Look for device named "NanoPi-NEO"

# Method 3: Scan your network from another computer
# On Windows (PowerShell):
arp -a

# On Linux/Mac:
nmap -sn 192.168.1.0/24
arp -a
```

### Fix Time Sync on Boot

The time sync service should already be installed (from previous fixes), but verify:

```bash
# Check if service exists
systemctl status timesync-on-boot.service

# If not found, run:
sudo bash fix_all_time_issues.sh
```

**How it works:**
- Waits 10 seconds after boot for network
- Uses IP-based NTP servers (no DNS needed):
  - 216.239.35.0 (Google)
  - 129.6.15.28 (NIST)
  - 132.163.96.1 (NIST)
- Restarts NTP service
- Runs automatically on every boot

### Fix Static IP Issues

If your IP keeps changing or SSH is unreachable:

**Option 1: Set Static IP via Web Interface**
1. Access web interface at: `http://[current-ip]:5000`
2. Go to Settings/Network Configuration
3. Set static IP, subnet mask, gateway, DNS
4. Apply settings

**Option 2: Configure Static IP Manually**

For **netplan** systems (Ubuntu/Armbian):
```bash
sudo nano /etc/netplan/01-netcfg.yaml
```

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: no
      addresses:
        - 192.168.1.100/24
      gateway4: 192.168.1.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
```

Apply:
```bash
sudo netplan apply
```

For **dhcpcd** systems (Raspberry Pi style):
```bash
sudo nano /etc/dhcpcd.conf
```

Add at the end:
```
interface eth0
static ip_address=192.168.1.100/24
static routers=192.168.1.1
static domain_name_servers=8.8.8.8 8.8.4.4
```

Apply:
```bash
sudo systemctl restart dhcpcd
```

### Enable SSH Permanently

Ensure SSH starts on boot:

```bash
sudo systemctl enable ssh
sudo systemctl start ssh
sudo systemctl status ssh
```

### Reserve IP in Router

**Best long-term solution:**

1. Login to your router admin panel
2. Find DHCP settings
3. Add **DHCP reservation** for NanoPi MAC address
4. Set it to always get the same IP (e.g., 192.168.1.100)

This way:
- NanoPi uses DHCP (simpler)
- Always gets the same IP address
- No manual IP configuration needed
- Survives reboots and network changes

## Prevention Strategies

### 1. Document Current Configuration

Create a file on the NanoPi:

```bash
sudo nano /root/network_info.txt
```

Add:
```
NanoPi Network Configuration
============================
Hostname: NanoPi-NEO
IP Address: 192.168.1.100
Subnet: 255.255.255.0 (/24)
Gateway: 192.168.1.1
DNS: 8.8.8.8, 8.8.4.4

MAC Address: [run: ip link show eth0 | grep ether]
Configuration Type: Static (or DHCP Reserved)

Web Interface: http://192.168.1.100:5000
SSH Access: ssh root@192.168.1.100

Last Updated: [date]
```

### 2. Monitor System Health

Add a cron job to email you if system has issues:

```bash
# Add to /etc/cron.daily/health-check.sh
#!/bin/bash
cd /opt/bellnews
./diagnose_and_fix_connectivity.sh > /tmp/health.txt
# Email or log the results
```

### 3. Set Up Serial Console (Advanced)

For emergency access without network:
- Connect USB-to-Serial adapter
- Access via serial console even if network fails
- See NanoPi NEO documentation for pinout

## Diagnostic Script Usage

The `diagnose_and_fix_connectivity.sh` script provides:

### What it Checks:
1. **System Time** - Verifies clock is correct
2. **Network** - Checks interfaces, gateway, DNS, internet
3. **SSH Service** - Ensures SSH is running and listening
4. **Disk Space** - Verifies adequate free space
5. **Journal Size** - Checks if logs are too large
6. **BellNews Services** - Status of web and alarm services
7. **System Resources** - Memory and CPU load

### What it Fixes Automatically:
- Syncs time with NTP if wrong
- Starts SSH if stopped
- Cleans journal if too large
- Restarts failed services
- Adds DNS servers if missing

### Output:
- Color-coded status messages
- Summary of all checks
- Recommended actions
- Log file for troubleshooting

## Troubleshooting Steps

### Cannot SSH In

1. **Find the IP address** (using methods above)
2. **Verify IP is reachable:**
   ```bash
   ping 192.168.1.100
   ```
3. **Check SSH port:**
   ```bash
   telnet 192.168.1.100 22
   # OR
   nmap -p 22 192.168.1.100
   ```
4. **Try different credentials** (default: root / bellnews)
5. **Use physical access** to run diagnostic script

### Web Interface Shows Wrong Time

1. **Hard refresh browser** (Ctrl+F5 or Ctrl+Shift+R)
2. **Check time on NanoPi:**
   ```bash
   date
   timedatectl
   ```
3. **Force time sync:**
   ```bash
   sudo ntpdate -s 216.239.35.0
   sudo systemctl restart ntp
   ```
4. **Restart web service:**
   ```bash
   sudo systemctl restart bellnews.service
   ```

### Network Keeps Dropping

1. **Check network cable** - Try different cable
2. **Check router port** - Try different port on router
3. **Check switch** - If using network switch, bypass it
4. **Check logs:**
   ```bash
   sudo journalctl -u NetworkManager -f
   sudo dmesg | grep -i eth0
   ```

## Files in This Fix

1. **diagnose_and_fix_connectivity.sh** - Main diagnostic tool
2. **fix_all_time_issues.sh** - Time sync fix (already exists)
3. **fix_journal_disk_space.sh** - Journal cleanup fix (already exists)
4. **CONNECTIVITY_ISSUES_README.md** - This documentation

## Related Issues

This connectivity issue is **separate from**:

1. **Memory leak fix** (commit aa6aea0) - Prevented application halting
2. **Journal disk space fix** - Prevented system halting when logs filled disk

All fixes work together for stable operation:
- Memory fix → Prevents app crashes
- Journal fix → Prevents disk full halting
- Time sync fix → Ensures correct time after reboot
- Connectivity fix → Diagnoses network/SSH issues

## Quick Reference Commands

```bash
# Find IP address
ip addr show

# Check time
date
timedatectl

# Force time sync
sudo ntpdate -s 216.239.35.0

# Check SSH
sudo systemctl status ssh

# Check network
ip route
ping 8.8.8.8

# Run full diagnostic
sudo bash diagnose_and_fix_connectivity.sh

# View service logs
sudo journalctl -u bellnews -f
sudo journalctl -u alarm_player -f

# Restart all services
sudo systemctl restart bellnews.service
sudo systemctl restart alarm_player.service
sudo systemctl restart ssh
```

## Summary

**The issue is likely:**
- NanoPi rebooted (power outage, manual reboot, etc.)
- Time reset to 1984 (no RTC battery)
- Network came up but got different IP address
- SSH accessible at new IP, not old IP
- Time sync service may have failed if network was slow

**The solution:**
1. Use physical access or find new IP
2. Run `diagnose_and_fix_connectivity.sh`
3. Fix any issues it identifies
4. Set static IP or DHCP reservation
5. Verify time sync service is working
6. Document the configuration

This should resolve both the time and SSH connectivity issues.
