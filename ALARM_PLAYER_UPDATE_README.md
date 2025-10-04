# BellNews Alarm Player Update

## Overview

This update adds the **missing alarm sound playback component** to your BellNews system. After running the main installation, this update enables the Nano Pi to play bell sounds through its speakers/audio output when alarms trigger.

## What This Update Does

- ✅ Installs the `alarm_player.py` service that monitors alarms and plays sounds
- ✅ Installs required audio dependencies (`pygame` library for MP3/WAV/OGG support)
- ✅ Configures systemd service for automatic startup
- ✅ Enables sound playback through Nano Pi hardware
- ✅ Supports multiple audio formats: **MP3, WAV, OGG**

## Prerequisites

1. **Main BellNews system must be installed first**
2. Must have root/sudo access
3. Nano Pi must have working audio output (speakers or audio jack)

## Installation Steps

### Step 1: Transfer Update Files

Transfer these 3 files to your Nano Pi bellapp directory:

```bash
alarm_player.py
alarm_player.service
update_alarm_player.sh
```

**Example using SCP:**
```bash
scp alarm_player.py alarm_player.service update_alarm_player.sh root@<nanopi-ip>:/root/bellapp/
```

### Step 2: Run the Update Script

SSH into your Nano Pi and run:

```bash
cd /root/bellapp  # or wherever your bellapp is installed
sudo bash update_alarm_player.sh
```

The script will:
- Install audio dependencies
- Install simpleaudio Python library
- Configure and start the alarm player service
- Verify everything is working

**Installation takes ~1-2 minutes**

### Step 3: Verify Installation

Check if the service is running:

```bash
sudo systemctl status alarm_player
```

You should see: **Active: active (running)**

View live logs:

```bash
sudo journalctl -u alarm_player -f
```

## Testing

1. Log into your BellNews web interface
2. Create a test alarm for 1-2 minutes from now
3. Wait for the alarm time
4. ✅ Sound should play through Nano Pi speakers!

## How It Works

### Before This Update
- Web interface could manage alarms
- BUT sounds only played in the web browser (not useful for a bell system!)

### After This Update
- New `alarm_player.py` service runs in the background
- Monitors `alarms.json` file every 5 seconds
- When an alarm time matches, plays sound through Nano Pi speakers
- Sounds play even when no one is logged into the web interface

## Service Management Commands

```bash
# Check service status
sudo systemctl status alarm_player

# View logs (live)
sudo journalctl -u alarm_player -f

# View service log file
tail -f /root/bellapp/logs/alarm_player.log

# Restart service
sudo systemctl restart alarm_player

# Stop service
sudo systemctl stop alarm_player

# Start service
sudo systemctl start alarm_player

# Disable auto-start
sudo systemctl disable alarm_player

# Enable auto-start (on by default)
sudo systemctl enable alarm_player
```

## Troubleshooting

### No Sound Playing

1. **Check if service is running:**
   ```bash
   sudo systemctl status alarm_player
   ```

2. **Check audio output:**
   ```bash
   # Test system audio
   speaker-test -t wav -c 2

   # Check volume (should be above 0%)
   amixer

   # Increase volume if needed
   amixer set Master 80%
   ```

3. **Check logs for errors:**
   ```bash
   sudo journalctl -u alarm_player -n 50
   ```

4. **Verify audio files exist:**
   ```bash
   ls -lh /root/bellapp/static/audio/
   ```

### Service Won't Start

```bash
# Check for errors
sudo journalctl -u alarm_player -n 50

# Try running manually to see errors
cd /root/bellapp
python3 alarm_player.py
```

### simpleaudio Installation Fails

If you get errors during installation:

```bash
# Install build dependencies
sudo apt-get install python3-dev libasound2-dev

# Try installing again
pip3 install simpleaudio
```

## File Locations

- **Service:** `/etc/systemd/system/alarm_player.service`
- **Python Script:** `/root/bellapp/alarm_player.py`
- **Logs:** `/root/bellapp/logs/alarm_player.log`
- **System Log:** `sudo journalctl -u alarm_player`
- **Alarms Data:** `/root/bellapp/alarms.json`
- **Audio Files:** `/root/bellapp/static/audio/`

## Audio File Requirements

- **Formats:** MP3, WAV, OGG (all fully supported via pygame)
- **Location:** `/root/bellapp/static/audio/` or `/opt/bellnews/static/audio/`
- **Upload:** Use the web interface to upload sound files
- **Recommended:** MP3 for smaller file sizes, WAV for best compatibility

## Uninstalling (If Needed)

```bash
# Stop and disable service
sudo systemctl stop alarm_player
sudo systemctl disable alarm_player

# Remove service file
sudo rm /etc/systemd/system/alarm_player.service

# Reload systemd
sudo systemctl daemon-reload

# Remove Python script (optional)
rm /root/bellapp/alarm_player.py
```

## For New Installations

If installing on a **new Nano Pi from scratch:**

1. **First:** Run the main BellNews installation script
2. **Then:** Run this update script (`update_alarm_player.sh`)

This two-step process ensures:
- Main system is properly installed
- Audio components are added on top
- No conflicts with existing installation

## Support

If you encounter issues:

1. Check the logs: `sudo journalctl -u alarm_player -f`
2. Verify audio output works: `speaker-test -t wav -c 2`
3. Ensure alarms are configured in the web interface
4. Check system time is correct: `date`

## Summary

**Before Update:** ❌ Alarms configured but no sounds on Nano Pi
**After Update:** ✅ Alarms play sounds through Nano Pi speakers automatically

Enjoy your fully functional BellNews system! 🔔



  Both Methods Work:

  Method 1: Using bash (no chmod needed)

  sudo bash update_alarm_player.sh
  ✅ Works immediately after file transfer

  Method 2: Direct execution (needs chmod first)

  chmod +x update_alarm_player.sh
  sudo ./update_alarm_player.sh

  💡 Recommendation

  Use Method 1 (sudo bash update_alarm_player.sh) because:
  - ✅ One less step
  - ✅ Works immediately
  - ✅ No permission issues
  - ✅ Easier to document

  So your workflow on the Nano Pi is simply:

  cd /root/bellapp
  sudo bash update_alarm_player.sh