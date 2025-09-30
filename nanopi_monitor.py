#!/usr/bin/env python3
"""
NanoPi NEO OLED System Monitor
A robust, self-installing system monitor for NanoPi NEO with OLED display
Supports multiple time zones, system monitoring, and button interactions
"""

import os
import sys
import time
import json
import threading
import subprocess
from datetime import datetime, timezone
import signal
import logging
from pathlib import Path

# Auto-install required packages
def install_packages():
    """Install required packages if not available"""
    required_packages = [
        'luma.oled',
        'psutil',
        'pytz',
        'Pillow'
    ]
    
    # Add GPIO package based on platform
    try:
        # Try to detect if we're on Orange Pi/NanoPi
        if os.path.exists('/proc/device-tree/model'):
            with open('/proc/device-tree/model', 'r') as f:
                model = f.read().lower()
                if 'orange' in model or 'nanopi' in model:
                    required_packages.append('OPi.GPIO')
                else:
                    required_packages.append('RPi.GPIO')  # Fallback for Raspberry Pi
        else:
            print("Warning: Could not detect board type, GPIO functionality may not work")
    except Exception as e:
        print(f"Warning: Could not detect board type: {e}")
   
    for package in required_packages:
        try:
            # Handle different import names
            import_name = package.replace('-', '_').replace('.', '_')
            if package == 'OPi.GPIO':
                import_name = 'OPi.GPIO'
            elif package == 'RPi.GPIO':
                import_name = 'RPi.GPIO'
            
            __import__(import_name)
            print(f"✓ {package} already installed")
        except ImportError:
            print(f"Installing {package}...")
            try:
                subprocess.check_call([sys.executable, '-m', 'pip', 'install', package])
                print(f"✓ {package} installed successfully")
            except subprocess.CalledProcessError as e:
                print(f"✗ Failed to install {package}: {e}")
                if package in ['OPi.GPIO', 'RPi.GPIO']:
                    print("  GPIO functionality will be disabled")
                else:
                    print(f"  {package} is required, please install manually")

# Install packages first
print("Checking and installing required packages...")
install_packages()

# Now import the packages with error handling
try:
    from luma.core.interface.serial import i2c
    from luma.core.render import canvas
    from luma.oled.device import ssd1306
    from PIL import Image, ImageDraw, ImageFont
    import psutil
    import pytz
    LUMA_AVAILABLE = True
except ImportError as e:
    print(f"Warning: OLED display modules not available: {e}")
    LUMA_AVAILABLE = False

# GPIO imports with fallback
GPIO_AVAILABLE = False
GPIO = None
try:
    import OPi.GPIO as GPIO
    GPIO_AVAILABLE = True
    GPIO_TYPE = "OPi"
    print("✓ Using OPi.GPIO")
except ImportError:
    try:
        import RPi.GPIO as GPIO
        GPIO_AVAILABLE = True
        GPIO_TYPE = "RPi"
        print("✓ Using RPi.GPIO")
    except ImportError:
        print("Warning: No GPIO library available, button functionality disabled")

class MockDevice:
    """Mock device for testing without hardware"""
    def __init__(self):
        pass
    
    def contrast(self, value):
        pass
    
    def cleanup(self):
        pass

class MockCanvas:
    """Mock canvas for testing without hardware"""
    def __init__(self, device):
        self.device = device
        
    def __enter__(self):
        return MockDraw()
        
    def __exit__(self, *args):
        pass

class MockDraw:
    """Mock draw for testing without hardware"""
    def text(self, position, text, fill="white"):
        print(f"Display: {text}")

def mock_canvas(device):
    return MockCanvas(device)

class NanoPiOLEDMonitor:
    def __init__(self):
        self.config_file = Path.home() / '.nanopi_monitor_config.json'
        self.log_file = Path.home() / '.nanopi_monitor.log'
       
        # Setup logging
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(self.log_file),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)
       
        # Configuration
        self.config = self.load_config()
       
        # Display modes
        self.display_modes = [
            'datetime',
            'system_info',
            'network_info',
            'temperature'
        ]
        self.current_mode = 0
       
        # GPIO setup for buttons (F1, F2, F3)
        self.button_pins = [6, 1, 67]  # Adjust based on your wiring
        self.gpio_initialized = False
        if GPIO_AVAILABLE:
            self.setup_gpio()
       
        # OLED setup
        self.setup_display()
       
        # Time zone
        try:
            self.timezone = pytz.timezone(self.config.get('timezone', 'UTC'))
        except:
            self.timezone = pytz.UTC
       
        # Threading
        self.running = True
        self.display_lock = threading.Lock()
       
        # NTP sync
        self.last_ntp_sync = 0
        self.ntp_sync_interval = 3600  # 1 hour
       
        self.logger.info("NanoPi OLED Monitor initialized")

    def load_config(self):
        """Load configuration from file"""
        default_config = {
            'timezone': 'UTC',
            'display_brightness': 255,
            'auto_brightness': True,
            'ntp_servers': ['pool.ntp.org', 'time.google.com'],
            'display_timeout': 0,  # 0 = never timeout
            'refresh_rate': 1.0,
            'mock_mode': not LUMA_AVAILABLE  # Enable mock mode if hardware not available
        }
       
        if self.config_file.exists():
            try:
                with open(self.config_file, 'r') as f:
                    config = json.load(f)
                    default_config.update(config)
            except Exception as e:
                self.logger.warning(f"Could not load config: {e}")
       
        return default_config

    def save_config(self):
        """Save configuration to file"""
        try:
            with open(self.config_file, 'w') as f:
                json.dump(self.config, f, indent=2)
        except Exception as e:
            self.logger.error(f"Could not save config: {e}")

    def setup_gpio(self):
        """Setup GPIO for buttons"""
        if not GPIO_AVAILABLE:
            self.logger.warning("GPIO not available, button functionality disabled")
            return
            
        try:
            if GPIO_TYPE == "OPi":
                GPIO.setmode(GPIO.BCM)
            else:  # RPi
                GPIO.setmode(GPIO.BCM)
                
            GPIO.setwarnings(False)
           
            for pin in self.button_pins:
                try:
                    GPIO.setup(pin, GPIO.IN, pull_up_down=GPIO.PUD_UP)
                    GPIO.add_event_detect(
                        pin, GPIO.FALLING,
                        callback=self.button_callback,
                        bouncetime=200
                    )
                except Exception as e:
                    self.logger.warning(f"Could not setup GPIO pin {pin}: {e}")
           
            self.gpio_initialized = True
            self.logger.info("GPIO setup completed")
        except Exception as e:
            self.logger.warning(f"GPIO setup failed: {e}")

    def setup_display(self):
        """Setup OLED display"""
        if not LUMA_AVAILABLE or self.config.get('mock_mode', False):
            self.logger.info("Using mock display (hardware not available)")
            self.device = MockDevice()
            self.canvas_func = mock_canvas
            return
            
        try:
            # Try different I2C addresses
            addresses = [0x3C, 0x3D]
            self.device = None
           
            for addr in addresses:
                try:
                    serial = i2c(port=1, address=addr)
                    self.device = ssd1306(serial, width=128, height=64)
                    self.device.contrast(self.config['display_brightness'])
                    self.canvas_func = canvas
                    self.logger.info(f"OLED initialized at address 0x{addr:02X}")
                    break
                except Exception as e:
                    self.logger.debug(f"Failed to initialize OLED at 0x{addr:02X}: {e}")
                    continue
           
            if not self.device:
                self.logger.warning("Could not initialize OLED display, using mock mode")
                self.device = MockDevice()
                self.canvas_func = mock_canvas
               
        except Exception as e:
            self.logger.error(f"Display setup failed: {e}")
            self.device = MockDevice()
            self.canvas_func = mock_canvas

    def button_callback(self, channel):
        """Handle button press"""
        try:
            if channel == self.button_pins[0]:  # F1 - Change display mode
                self.current_mode = (self.current_mode + 1) % len(self.display_modes)
                self.logger.info(f"Switched to mode: {self.display_modes[self.current_mode]}")
           
            elif channel == self.button_pins[1]:  # F2 - Change timezone
                self.cycle_timezone()
           
            elif channel == self.button_pins[2]:  # F3 - Force NTP sync
                self.sync_ntp()
               
        except Exception as e:
            self.logger.error(f"Button callback error: {e}")

    def cycle_timezone(self):
        """Cycle through common timezones"""
        timezones = [
            'UTC', 'US/Eastern', 'US/Pacific', 'Europe/London', 'Europe/Berlin',
            'Asia/Shanghai', 'Asia/Tokyo', 'Australia/Sydney'
        ]
       
        try:
            current_tz = self.config['timezone']
            current_index = timezones.index(current_tz) if current_tz in timezones else 0
            next_index = (current_index + 1) % len(timezones)
           
            self.config['timezone'] = timezones[next_index]
            self.timezone = pytz.timezone(timezones[next_index])
            self.save_config()
           
            self.logger.info(f"Timezone changed to: {timezones[next_index]}")
        except Exception as e:
            self.logger.error(f"Timezone change error: {e}")

    def sync_ntp(self):
        """Synchronize time with NTP servers"""
        try:
            # Check if running as root for ntpdate
            if os.geteuid() != 0:
                self.logger.warning("NTP sync requires root privileges")
                return False
                
            for server in self.config['ntp_servers']:
                try:
                    # Try ntpdate first
                    result = subprocess.run(['which', 'ntpdate'], 
                                          capture_output=True, text=True)
                    if result.returncode == 0:
                        subprocess.check_call(['ntpdate', '-s', server],
                                            timeout=10,
                                            stdout=subprocess.DEVNULL,
                                            stderr=subprocess.DEVNULL)
                    else:
                        # Fallback to systemd-timesyncd or chrony
                        subprocess.check_call(['systemctl', 'restart', 'systemd-timesyncd'],
                                            timeout=10,
                                            stdout=subprocess.DEVNULL,
                                            stderr=subprocess.DEVNULL)
                    
                    self.last_ntp_sync = time.time()
                    self.logger.info(f"NTP sync successful with {server}")
                    return True
                except Exception as e:
                    self.logger.debug(f"NTP sync failed with {server}: {e}")
                    continue
           
            self.logger.warning("All NTP sync attempts failed")
            return False
           
        except Exception as e:
            self.logger.error(f"NTP sync error: {e}")
            return False

    def get_system_info(self):
        """Get system information"""
        try:
            cpu_percent = psutil.cpu_percent(interval=0.1)
            memory = psutil.virtual_memory()
            disk = psutil.disk_usage('/')
           
            return {
                'cpu': cpu_percent,
                'memory_percent': memory.percent,
                'memory_used': memory.used // (1024**2),  # MB
                'memory_total': memory.total // (1024**2),  # MB
                'disk_percent': disk.percent,
                'disk_used': disk.used // (1024**3),  # GB
                'disk_total': disk.total // (1024**3)  # GB
            }
        except Exception as e:
            self.logger.error(f"System info error: {e}")
            return None

    def get_network_info(self):
        """Get network information"""
        try:
            # Get IP address
            ip_addresses = []
            try:
                result = subprocess.run(['hostname', '-I'],
                                      capture_output=True, text=True, timeout=5)
                ip_addresses = result.stdout.strip().split()
            except:
                # Fallback method
                try:
                    import socket
                    hostname = socket.gethostname()
                    ip_addresses = [socket.gethostbyname(hostname)]
                except:
                    ip_addresses = ['Unknown']
           
            # Get network stats
            try:
                net_io = psutil.net_io_counters()
                bytes_sent = net_io.bytes_sent // (1024**2)  # MB
                bytes_recv = net_io.bytes_recv // (1024**2)  # MB
            except:
                bytes_sent = 0
                bytes_recv = 0
           
            return {
                'ip_addresses': ip_addresses,
                'bytes_sent': bytes_sent,
                'bytes_recv': bytes_recv,
            }
        except Exception as e:
            self.logger.error(f"Network info error: {e}")
            return None

    def get_temperature(self):
        """Get system temperature"""
        try:
            # Try multiple temperature sources
            temp_files = [
                '/sys/class/thermal/thermal_zone0/temp',
                '/sys/class/hwmon/hwmon0/temp1_input',
                '/sys/class/hwmon/hwmon1/temp1_input'
            ]
           
            for temp_file in temp_files:
                try:
                    if os.path.exists(temp_file):
                        with open(temp_file, 'r') as f:
                            temp = int(f.read().strip()) / 1000.0
                            return temp
                except Exception as e:
                    self.logger.debug(f"Could not read {temp_file}: {e}")
                    continue
           
            # Fallback to psutil if available
            try:
                temps = psutil.sensors_temperatures()
                if temps:
                    for name, entries in temps.items():
                        if entries:
                            return entries[0].current
            except:
                pass
           
            return None
           
        except Exception as e:
            self.logger.error(f"Temperature reading error: {e}")
            return None

    def draw_datetime(self, draw, width, height):
        """Draw date and time display"""
        try:
            now = datetime.now(self.timezone)
           
            # Date
            date_str = now.strftime("%a, %b %d %Y")
           
            # Time
            time_str = now.strftime("%H:%M:%S")
           
            # Timezone
            tz_str = str(self.timezone).split('/')[-1]
           
            # Draw text
            draw.text((0, 0), date_str, fill="white")
            draw.text((0, 20), time_str, fill="white")
            draw.text((0, 40), f"TZ: {tz_str}", fill="white")
           
        except Exception as e:
            draw.text((0, 0), f"Time Error: {str(e)[:15]}", fill="white")

    def draw_system_info(self, draw, width, height):
        """Draw system information"""
        try:
            info = self.get_system_info()
            if not info:
                draw.text((0, 0), "System info unavailable", fill="white")
                return
           
            draw.text((0, 0), f"CPU: {info['cpu']:.1f}%", fill="white")
            draw.text((0, 12), f"RAM: {info['memory_percent']:.1f}%", fill="white")
            draw.text((0, 24), f"     {info['memory_used']}MB/{info['memory_total']}MB", fill="white")
            draw.text((0, 36), f"Disk: {info['disk_percent']:.1f}%", fill="white")
            draw.text((0, 48), f"      {info['disk_used']}GB/{info['disk_total']}GB", fill="white")
           
        except Exception as e:
            draw.text((0, 0), f"Sys Error: {str(e)[:15]}", fill="white")

    def draw_network_info(self, draw, width, height):
        """Draw network information"""
        try:
            info = self.get_network_info()
            if not info:
                draw.text((0, 0), "Network info unavailable", fill="white")
                return
           
            draw.text((0, 0), "Network Info", fill="white")
           
            y_pos = 12
            for ip in info['ip_addresses'][:2]:  # Show max 2 IPs
                draw.text((0, y_pos), f"IP: {ip}", fill="white")
                y_pos += 12
           
            draw.text((0, y_pos), f"TX: {info['bytes_sent']}MB", fill="white")
            draw.text((0, y_pos + 12), f"RX: {info['bytes_recv']}MB", fill="white")
           
        except Exception as e:
            draw.text((0, 0), f"Net Error: {str(e)[:15]}", fill="white")

    def draw_temperature(self, draw, width, height):
        """Draw temperature information"""
        try:
            temp = self.get_temperature()
           
            draw.text((0, 0), "Temperature", fill="white")
           
            if temp is not None:
                draw.text((0, 20), f"CPU: {temp:.1f}°C", fill="white")
               
                # Temperature status
                if temp < 50:
                    status = "COOL"
                elif temp < 70:
                    status = "WARM"
                else:
                    status = "HOT!"
               
                draw.text((0, 40), f"Status: {status}", fill="white")
            else:
                draw.text((0, 20), "Temperature sensor", fill="white")
                draw.text((0, 32), "not available", fill="white")
               
        except Exception as e:
            draw.text((0, 0), f"Temp Error: {str(e)[:15]}", fill="white")

    def update_display(self):
        """Update the OLED display"""
        try:
            with self.display_lock:
                if not self.device:
                    return
               
                with self.canvas_func(self.device) as draw:
                    mode = self.display_modes[self.current_mode]
                   
                    if mode == 'datetime':
                        self.draw_datetime(draw, 128, 64)
                    elif mode == 'system_info':
                        self.draw_system_info(draw, 128, 64)
                    elif mode == 'network_info':
                        self.draw_network_info(draw, 128, 64)
                    elif mode == 'temperature':
                        self.draw_temperature(draw, 128, 64)
                   
        except Exception as e:
            self.logger.error(f"Display update error: {e}")

    def auto_ntp_sync(self):
        """Automatically sync NTP if needed"""
        if time.time() - self.last_ntp_sync > self.ntp_sync_interval:
            self.sync_ntp()

    def display_thread(self):
        """Main display update thread"""
        while self.running:
            try:
                self.auto_ntp_sync()
                self.update_display()
                time.sleep(self.config['refresh_rate'])
            except Exception as e:
                self.logger.error(f"Display thread error: {e}")
                time.sleep(5)

    def signal_handler(self, signum, frame):
        """Handle shutdown signals"""
        self.logger.info("Shutdown signal received")
        self.running = False

    def run(self):
        """Main run method"""
        # Setup signal handlers
        signal.signal(signal.SIGINT, self.signal_handler)
        signal.signal(signal.SIGTERM, self.signal_handler)
       
        # Initial NTP sync (only if root)
        if os.geteuid() == 0:
            self.sync_ntp()
        else:
            self.logger.info("Running without root privileges, NTP sync disabled")
       
        # Start display thread
        display_thread = threading.Thread(target=self.display_thread)
        display_thread.daemon = True
        display_thread.start()
       
        self.logger.info("NanoPi OLED Monitor started")
        if self.config.get('mock_mode', False):
            self.logger.info("Running in mock mode (no hardware)")
       
        try:
            # Keep main thread alive
            while self.running:
                time.sleep(1)
        except KeyboardInterrupt:
            pass
        finally:
            self.cleanup()

    def cleanup(self):
        """Cleanup resources"""
        self.logger.info("Cleaning up...")
        self.running = False
       
        try:
            if self.device and hasattr(self.device, 'cleanup'):
                self.device.cleanup()
        except:
            pass
       
        try:
            if GPIO_AVAILABLE and self.gpio_initialized:
                GPIO.cleanup()
        except:
            pass
       
        self.logger.info("Cleanup completed")

def create_systemd_service():
    """Create systemd service for auto-start"""
    service_content = f"""[Unit]
Description=NanoPi OLED Monitor
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory={Path.home()}
ExecStart={sys.executable} {os.path.abspath(__file__)}
Restart=always
RestartSec=10
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
"""
   
    service_path = Path('/etc/systemd/system/nanopi-oled-monitor.service')
   
    try:
        if os.geteuid() != 0:
            print("Error: Installing systemd service requires root privileges")
            print("Please run with sudo: sudo python3 script.py --install-service")
            return
            
        with open(service_path, 'w') as f:
            f.write(service_content)
       
        subprocess.run(['systemctl', 'daemon-reload'], check=True)
        subprocess.run(['systemctl', 'enable', 'nanopi-oled-monitor.service'], check=True)
       
        print("✓ Systemd service created and enabled")
        print("Use 'sudo systemctl start nanopi-oled-monitor' to start")
        print("Use 'sudo systemctl status nanopi-oled-monitor' to check status")
        print("Use 'sudo systemctl stop nanopi-oled-monitor' to stop")
       
    except Exception as e:
        print(f"✗ Failed to create systemd service: {e}")

def print_usage():
    """Print usage information"""
    print("NanoPi NEO OLED System Monitor")
    print("Usage:")
    print(f"  {sys.argv[0]}                    - Run the monitor")
    print(f"  {sys.argv[0]} --install-service  - Install systemd service")
    print(f"  {sys.argv[0]} --help             - Show this help")
    print("\nFeatures:")
    print("  - System monitoring (CPU, RAM, Disk, Temperature)")
    print("  - Network information display")
    print("  - Multiple timezone support")
    print("  - Button controls (if GPIO available)")
    print("  - Auto NTP synchronization")
    print("  - Mock mode for testing without hardware")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        if sys.argv[1] == '--install-service':
            create_systemd_service()
            sys.exit(0)
        elif sys.argv[1] == '--help':
            print_usage()
            sys.exit(0)
        else:
            print(f"Unknown argument: {sys.argv[1]}")
            print_usage()
            sys.exit(1)
   
    monitor = NanoPiOLEDMonitor()
    monitor.run()