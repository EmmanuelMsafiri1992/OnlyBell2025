#!/usr/bin/env python3
"""
Alarm Player Service for BellNews System
Monitors alarms.json and plays sounds at scheduled times through system speakers
Supports: MP3, WAV, OGG, and other audio formats
"""

import os
import sys
import json
import time
import logging
import threading
import signal
from pathlib import Path
from datetime import datetime
import pytz

# Try to import pygame for audio playback (supports MP3, WAV, OGG, etc.)
try:
    import pygame
    pygame.mixer.init()
    # Check if pygame.mixer.music is available
    if hasattr(pygame.mixer, 'music'):
        AUDIO_AVAILABLE = True
        AUDIO_ENGINE = "pygame"
    else:
        # Custom pygame without music support, fallback to simpleaudio
        raise AttributeError("pygame.mixer.music not available")
except (ImportError, AttributeError, Exception):
    # Fallback to simpleaudio (WAV only)
    try:
        import simpleaudio as sa
        AUDIO_AVAILABLE = True
        AUDIO_ENGINE = "simpleaudio"
    except ImportError:
        AUDIO_AVAILABLE = False
        AUDIO_ENGINE = "none"
        print("WARNING: No audio library installed. Audio playback will not work.")
        print("Install with: pip3 install pygame (recommended) or pip3 install simpleaudio")

# Configure paths
BASE_DIR = Path(__file__).resolve().parent
LOG_DIR = BASE_DIR / "logs"
LOG_FILE = LOG_DIR / "alarm_player.log"
ALARMS_FILE = BASE_DIR / "alarms.json"
AUDIO_DIR = BASE_DIR / "static" / "audio"

# Ensure logs directory exists
os.makedirs(LOG_DIR, exist_ok=True)

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger("AlarmPlayer")

# Global state
shutdown_requested = False
play_object = None  # Track currently playing audio


class AlarmPlayer:
    def __init__(self):
        self.alarms = []
        self.triggered_alarms = {}  # Track which alarms were triggered {alarm_id: last_triggered_date}
        self.lock = threading.Lock()
        logger.info("Alarm Player initialized")

    def load_alarms(self):
        """Load alarms from JSON file"""
        if not ALARMS_FILE.exists():
            logger.warning(f"Alarms file not found: {ALARMS_FILE}")
            return []

        try:
            with open(ALARMS_FILE, 'r') as f:
                data = json.load(f)
                if isinstance(data, list):
                    logger.info(f"Loaded {len(data)} alarms from file")
                    return data
                else:
                    logger.warning(f"Invalid alarms data format, expected list")
                    return []
        except json.JSONDecodeError as e:
            logger.error(f"Failed to decode alarms JSON: {e}")
            return []
        except Exception as e:
            logger.error(f"Error loading alarms: {e}")
            return []

    def check_alarm_time(self, alarm, now):
        """Check if alarm should trigger at current time"""
        try:
            # Get current day name
            current_day = now.strftime("%A")

            # Check if alarm is for today
            if alarm.get('day') != current_day:
                return False

            # Parse alarm time (format: "HH:MM")
            alarm_time = alarm.get('time', '')
            if not alarm_time:
                return False

            alarm_hour, alarm_minute = map(int, alarm_time.split(':'))

            # Check if current time matches alarm time (within same minute)
            if now.hour == alarm_hour and now.minute == alarm_minute:
                # Check if we already triggered this alarm today
                alarm_id = alarm.get('id', alarm_time)
                today_date = now.strftime("%Y-%m-%d")

                with self.lock:
                    last_triggered = self.triggered_alarms.get(alarm_id)
                    if last_triggered == today_date:
                        # Already triggered today
                        return False

                    # Mark as triggered for today
                    self.triggered_alarms[alarm_id] = today_date
                    return True

            return False

        except Exception as e:
            logger.error(f"Error checking alarm time: {e}")
            return False

    def play_sound(self, sound_file):
        """Play sound file through system speakers"""
        global play_object

        if not AUDIO_AVAILABLE:
            logger.error(f"Cannot play sound - no audio library available (engine: {AUDIO_ENGINE})")
            return False

        sound_path = AUDIO_DIR / sound_file

        if not sound_path.exists():
            logger.error(f"Sound file not found: {sound_path}")
            return False

        try:
            logger.info(f"Playing sound: {sound_file} (engine: {AUDIO_ENGINE})")

            if AUDIO_ENGINE == "pygame":
                # Use pygame mixer (supports MP3, WAV, OGG)
                pygame.mixer.music.load(str(sound_path))
                pygame.mixer.music.play()

                # Wait for sound to finish
                while pygame.mixer.music.get_busy():
                    time.sleep(0.1)

                logger.info(f"Finished playing: {sound_file}")
                return True

            elif AUDIO_ENGINE == "simpleaudio":
                # Use aplay directly (most stable for ARM devices)
                import subprocess

                # If file is MP3/OGG, convert to WAV using ffmpeg
                temp_file = None
                if sound_file.lower().endswith(('.mp3', '.ogg')):
                    logger.info(f"Converting {sound_file} to WAV for playback")
                    wav_path = sound_path.parent / f"{sound_path.stem}_temp.wav"
                    try:
                        result = subprocess.run(
                            ['ffmpeg', '-i', str(sound_path), '-y', str(wav_path)],
                            stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE,
                            timeout=10
                        )
                        if result.returncode != 0:
                            logger.error(f"FFmpeg failed: {result.stderr.decode()}")
                            return False
                        sound_path = wav_path
                        temp_file = wav_path
                    except subprocess.TimeoutExpired:
                        logger.error(f"FFmpeg conversion timeout for: {sound_file}")
                        return False
                    except Exception as e:
                        logger.error(f"FFmpeg conversion error: {e}")
                        return False

                # Play using aplay (system audio player)
                try:
                    logger.info(f"Playing WAV file with aplay: {sound_path.name}")
                    result = subprocess.run(
                        ['aplay', str(sound_path)],
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        timeout=30
                    )
                    if result.returncode != 0:
                        logger.error(f"aplay failed: {result.stderr.decode()}")
                        return False
                except Exception as e:
                    logger.error(f"aplay error: {e}")
                    return False
                finally:
                    # Clean up temp file
                    if temp_file and temp_file.exists():
                        try:
                            temp_file.unlink()
                        except:
                            pass

                logger.info(f"Finished playing: {sound_file}")
                return True

            else:
                logger.error("No audio engine available")
                return False

        except Exception as e:
            logger.error(f"Error playing sound {sound_file}: {e}")
            return False

    def trigger_alarm(self, alarm):
        """Trigger an alarm by playing its sound"""
        alarm_label = alarm.get('label', 'Alarm')
        alarm_time = alarm.get('time', 'Unknown')
        sound_file = alarm.get('sound', '')

        logger.info(f"Triggering alarm: {alarm_label} at {alarm_time}")

        if not sound_file:
            logger.warning(f"Alarm has no sound file: {alarm_label}")
            return

        # Play sound in a separate thread to avoid blocking
        threading.Thread(
            target=self.play_sound,
            args=(sound_file,),
            daemon=True
        ).start()

    def monitor_alarms(self):
        """Main monitoring loop"""
        logger.info("Starting alarm monitoring...")

        last_minute = -1

        while not shutdown_requested:
            try:
                # Get current time
                now = datetime.now()
                current_minute = now.minute

                # Only check alarms once per minute (when minute changes)
                if current_minute != last_minute:
                    last_minute = current_minute

                    # Reload alarms (in case they were updated)
                    self.alarms = self.load_alarms()

                    # Check each alarm
                    for alarm in self.alarms:
                        if self.check_alarm_time(alarm, now):
                            self.trigger_alarm(alarm)

                # Clean up old triggered alarms (keep only today's)
                today_date = now.strftime("%Y-%m-%d")
                with self.lock:
                    self.triggered_alarms = {
                        k: v for k, v in self.triggered_alarms.items()
                        if v == today_date
                    }

                # Sleep for 5 seconds before next check
                time.sleep(5)

            except Exception as e:
                logger.error(f"Error in monitoring loop: {e}", exc_info=True)
                time.sleep(5)

        logger.info("Alarm monitoring stopped")

    def run(self):
        """Start the alarm player service"""
        logger.info("=" * 60)
        logger.info("BellNews Alarm Player Service Starting")
        logger.info(f"Audio Available: {AUDIO_AVAILABLE}")
        logger.info(f"Audio Engine: {AUDIO_ENGINE}")
        logger.info(f"Alarms File: {ALARMS_FILE}")
        logger.info(f"Audio Directory: {AUDIO_DIR}")
        logger.info("=" * 60)

        if not AUDIO_AVAILABLE:
            logger.error("CRITICAL: No audio library installed. Service will not play sounds.")
            logger.error("Please run: pip3 install pygame (recommended) or pip3 install simpleaudio")

        # Initial load
        self.alarms = self.load_alarms()

        # Start monitoring
        self.monitor_alarms()


def signal_handler(signum, frame):
    """Handle shutdown signals"""
    global shutdown_requested
    logger.info(f"Received signal {signum}, shutting down...")
    shutdown_requested = True

    # Stop any playing sound
    global play_object
    if play_object and play_object.is_playing():
        play_object.stop()

    sys.exit(0)


# Register signal handlers
signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)


if __name__ == "__main__":
    try:
        player = AlarmPlayer()
        player.run()
    except Exception as e:
        logger.critical(f"Fatal error: {e}", exc_info=True)
        sys.exit(1)
