# Updating Existing Nano Pi Installations

## Quick Update for Existing Nano Pis

If you have Nano Pis that were installed **before** the alarm sound fix, use this simple update script:

### Method 1: One-Command Update (Recommended)

SSH into each Nano Pi and run:

```bash
curl -sSL https://raw.githubusercontent.com/EmmanuelMsafiri1992/OnlyBell2025/main/update_existing_nanopi.sh | sudo bash
```

This will:
- ✅ Pull latest code from GitHub
- ✅ Configure audio routing to H3 Codec
- ✅ Set audio volume to 100%
- ✅ Install ffmpeg for MP3 conversion
- ✅ Update alarm_player.py with edit fix
- ✅ Restart services

**Takes ~2 minutes per Nano Pi**

---

### Method 2: Manual Update

If you prefer manual control:

```bash
# 1. SSH into Nano Pi
ssh root@<nanopi-ip>

# 2. Navigate to installation directory
cd /opt/bellnews

# 3. Download update script
wget https://raw.githubusercontent.com/EmmanuelMsafiri1992/OnlyBell2025/main/update_existing_nanopi.sh

# 4. Run update
sudo bash update_existing_nanopi.sh
```

---

### Method 3: Git Pull Update

If you already have git configured:

```bash
cd /opt/bellnews
git pull
sudo bash update_system.sh
```

---

## What Gets Fixed

### ✅ Alarm Sound Playback
- Sounds now play through Nano Pi hardware (not just browser)
- MP3, WAV, OGG formats supported
- Audio routed to correct hardware (H3 Audio Codec)

### ✅ Edited Alarms Work
- Fixed issue where edited alarms wouldn't trigger
- Can now edit alarm time and it will trigger at new time
- No need to delete and recreate alarms

### ✅ Audio Configuration
- ALSA configured to use H3 Audio Codec (card 2)
- Volume set to 100%
- Settings persist after reboot

---

## Verification

After update, test the system:

```bash
# 1. Check alarm player service
sudo systemctl status alarm_player

# 2. Test audio output
speaker-test -t wav -c 2 -l 1

# 3. Create test alarm via web interface
# Set for 2 minutes from now and verify it rings
```

---

## For New Installations

**Good news!** All new Nano Pi installations will work perfectly with alarm sounds right out of the box.

The main installer now includes:
- Alarm player setup
- Audio configuration
- All necessary dependencies

Just run the standard installer:

```bash
curl -sSL https://raw.githubusercontent.com/EmmanuelMsafiri1992/OnlyBell2025/main/install_bellnews.sh | bash
```

---

## Troubleshooting

### No Sound After Update

```bash
# Check audio routing
aplay -l

# Should show: card 2: Codec [H3 Audio Codec]

# Test audio manually
aplay /opt/bellnews/static/audio/*.mp3

# Check alarm service logs
sudo journalctl -u alarm_player -f
```

### Alarm Not Triggering

```bash
# Check alarm file format
cat /opt/bellnews/alarms.json

# Check current time matches
date

# Watch logs when alarm should trigger
sudo journalctl -u alarm_player -f
```

### Service Not Running

```bash
# Restart service
sudo systemctl restart alarm_player

# Check for errors
sudo systemctl status alarm_player

# View detailed logs
sudo journalctl -u alarm_player -n 50
```

---

## Summary

- **Existing Nano Pis**: Run `update_existing_nanopi.sh`
- **New Installations**: Standard installer works perfectly
- **Alarms**: Can be created, edited, and deleted via web interface
- **Audio**: MP3/WAV/OGG supported, plays through hardware

All issues are now fixed and pushed to GitHub! 🎉
