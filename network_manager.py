#!/usr/bin/env python3
"""
Network Manager for Bell News
Handles Ubuntu/NanoPi network configuration including static/dynamic IP settings
"""

import os
import sys
import subprocess
import json
import logging
import re
import time
from pathlib import Path

logger = logging.getLogger(__name__)

class NetworkManager:
    def __init__(self):
        self.interfaces_file = "/etc/network/interfaces"
        self.dhcpcd_file = "/etc/dhcpcd.conf"
        self.netplan_dir = "/etc/netplan"
        self.backup_dir = "/opt/bellnews/network_backups"

        # Ensure backup directory exists
        os.makedirs(self.backup_dir, exist_ok=True)

        # Detect network management system
        self.network_system = self.detect_network_system()
        logger.info(f"Detected network management system: {self.network_system}")

    def detect_network_system(self):
        """Detect which network management system is in use"""
        if os.path.exists(self.netplan_dir) and os.listdir(self.netplan_dir):
            return "netplan"
        elif os.path.exists(self.dhcpcd_file):
            return "dhcpcd"
        elif os.path.exists(self.interfaces_file):
            return "interfaces"
        else:
            return "unknown"

    def get_primary_interface(self):
        """Get the primary network interface"""
        try:
            # Get default route interface
            result = subprocess.run(['ip', 'route', 'show', 'default'],
                                  capture_output=True, text=True, check=True)

            # Extract interface from default route
            for line in result.stdout.split('\n'):
                if 'default' in line:
                    parts = line.split()
                    if 'dev' in parts:
                        dev_index = parts.index('dev')
                        if dev_index + 1 < len(parts):
                            interface = parts[dev_index + 1]
                            logger.info(f"Primary interface detected: {interface}")
                            return interface

            # Fallback: get first non-loopback interface
            result = subprocess.run(['ip', 'link', 'show'],
                                  capture_output=True, text=True, check=True)

            for line in result.stdout.split('\n'):
                if ': eth' in line or ': en' in line or ': wlan' in line:
                    interface = line.split(':')[1].strip()
                    logger.info(f"Fallback interface detected: {interface}")
                    return interface

        except Exception as e:
            logger.error(f"Error detecting interface: {e}")

        # Final fallback
        return "eth0"

    def backup_config(self):
        """Backup current network configuration"""
        timestamp = int(time.time())

        try:
            if self.network_system == "netplan":
                # Backup all netplan files
                for file_path in Path(self.netplan_dir).glob("*.yaml"):
                    backup_path = f"{self.backup_dir}/{file_path.name}.{timestamp}"
                    subprocess.run(['cp', str(file_path), backup_path], check=True)

            elif self.network_system == "dhcpcd":
                backup_path = f"{self.backup_dir}/dhcpcd.conf.{timestamp}"
                subprocess.run(['cp', self.dhcpcd_file, backup_path], check=True)

            elif self.network_system == "interfaces":
                backup_path = f"{self.backup_dir}/interfaces.{timestamp}"
                subprocess.run(['cp', self.interfaces_file, backup_path], check=True)

            logger.info(f"Network configuration backed up with timestamp {timestamp}")
            return True

        except Exception as e:
            logger.error(f"Failed to backup network configuration: {e}")
            return False

    def apply_network_config(self, config):
        """
        Apply network configuration based on detected system

        Args:
            config (dict): Network configuration
                {
                    'ipType': 'static' or 'dynamic',
                    'ipAddress': '192.168.1.100',
                    'subnetMask': '255.255.255.0',
                    'gateway': '192.168.1.1',
                    'dnsServer': '8.8.8.8'
                }
        """
        try:
            # Backup current config
            if not self.backup_config():
                return {'status': 'error', 'message': 'Failed to backup current configuration'}

            interface = self.get_primary_interface()

            if self.network_system == "netplan":
                result = self._apply_netplan_config(interface, config)
            elif self.network_system == "dhcpcd":
                result = self._apply_dhcpcd_config(interface, config)
            elif self.network_system == "interfaces":
                result = self._apply_interfaces_config(interface, config)
            else:
                return {'status': 'error', 'message': 'Unknown network management system'}

            if result['status'] == 'success':
                # Apply the configuration
                self._restart_networking()

            return result

        except Exception as e:
            logger.error(f"Error applying network config: {e}")
            return {'status': 'error', 'message': f'Failed to apply network configuration: {str(e)}'}

    def _apply_netplan_config(self, interface, config):
        """Apply configuration using netplan (Ubuntu 18.04+)"""
        try:
            netplan_file = f"{self.netplan_dir}/01-netcfg.yaml"

            if config['ipType'] == 'static':
                # Calculate CIDR from subnet mask
                cidr = self._subnet_mask_to_cidr(config.get('subnetMask', '255.255.255.0'))

                netplan_config = {
                    'network': {
                        'version': 2,
                        'renderer': 'networkd',
                        'ethernets': {
                            interface: {
                                'addresses': [f"{config['ipAddress']}/{cidr}"],
                                'gateway4': config.get('gateway', ''),
                                'nameservers': {
                                    'addresses': [config.get('dnsServer', '8.8.8.8')]
                                }
                            }
                        }
                    }
                }
            else:  # dynamic
                netplan_config = {
                    'network': {
                        'version': 2,
                        'renderer': 'networkd',
                        'ethernets': {
                            interface: {
                                'dhcp4': True
                            }
                        }
                    }
                }

            # Write netplan config
            with open(netplan_file, 'w') as f:
                import yaml
                yaml.dump(netplan_config, f, default_flow_style=False)

            # Set permissions
            os.chmod(netplan_file, 0o600)

            return {'status': 'success', 'message': 'Netplan configuration updated'}

        except Exception as e:
            logger.error(f"Error applying netplan config: {e}")
            return {'status': 'error', 'message': f'Netplan configuration failed: {str(e)}'}

    def _apply_dhcpcd_config(self, interface, config):
        """Apply configuration using dhcpcd"""
        try:
            # Read current dhcpcd.conf
            with open(self.dhcpcd_file, 'r') as f:
                lines = f.readlines()

            # Remove existing interface config
            new_lines = []
            skip_interface = False

            for line in lines:
                if line.startswith(f'interface {interface}'):
                    skip_interface = True
                    continue
                elif line.startswith('interface ') and skip_interface:
                    skip_interface = False
                elif skip_interface and (line.startswith('static ') or line.startswith('#')):
                    continue

                if not skip_interface:
                    new_lines.append(line)

            # Add new configuration
            if config['ipType'] == 'static':
                new_lines.append(f'\ninterface {interface}\n')
                new_lines.append(f'static ip_address={config["ipAddress"]}/{self._subnet_mask_to_cidr(config.get("subnetMask", "255.255.255.0"))}\n')
                if config.get('gateway'):
                    new_lines.append(f'static routers={config["gateway"]}\n')
                if config.get('dnsServer'):
                    new_lines.append(f'static domain_name_servers={config["dnsServer"]}\n')

            # Write updated config
            with open(self.dhcpcd_file, 'w') as f:
                f.writelines(new_lines)

            return {'status': 'success', 'message': 'DHCPCD configuration updated'}

        except Exception as e:
            logger.error(f"Error applying dhcpcd config: {e}")
            return {'status': 'error', 'message': f'DHCPCD configuration failed: {str(e)}'}

    def _apply_interfaces_config(self, interface, config):
        """Apply configuration using /etc/network/interfaces"""
        try:
            # Read current interfaces file
            with open(self.interfaces_file, 'r') as f:
                content = f.read()

            # Remove existing interface configuration
            lines = content.split('\n')
            new_lines = []
            skip_interface = False

            for line in lines:
                if line.startswith(f'auto {interface}') or line.startswith(f'iface {interface}'):
                    skip_interface = True
                    continue
                elif line.startswith('auto ') or line.startswith('iface '):
                    skip_interface = False
                elif skip_interface and (line.startswith('    ') or line.strip() == ''):
                    continue

                if not skip_interface:
                    new_lines.append(line)

            # Add new configuration
            new_lines.append(f'\nauto {interface}')

            if config['ipType'] == 'static':
                new_lines.append(f'iface {interface} inet static')
                new_lines.append(f'    address {config["ipAddress"]}')
                new_lines.append(f'    netmask {config.get("subnetMask", "255.255.255.0")}')
                if config.get('gateway'):
                    new_lines.append(f'    gateway {config["gateway"]}')
                if config.get('dnsServer'):
                    new_lines.append(f'    dns-nameservers {config["dnsServer"]}')
            else:  # dynamic
                new_lines.append(f'iface {interface} inet dhcp')

            # Write updated config
            with open(self.interfaces_file, 'w') as f:
                f.write('\n'.join(new_lines))

            return {'status': 'success', 'message': 'Network interfaces configuration updated'}

        except Exception as e:
            logger.error(f"Error applying interfaces config: {e}")
            return {'status': 'error', 'message': f'Network interfaces configuration failed: {str(e)}'}

    def _subnet_mask_to_cidr(self, subnet_mask):
        """Convert subnet mask to CIDR notation"""
        try:
            # Convert subnet mask to binary and count 1s
            binary = ''.join([bin(int(x))[2:].zfill(8) for x in subnet_mask.split('.')])
            return str(binary.count('1'))
        except:
            return '24'  # Default /24

    def _restart_networking(self):
        """Restart networking services"""
        try:
            if self.network_system == "netplan":
                subprocess.run(['netplan', 'apply'], check=True, timeout=30)
                logger.info("Applied netplan configuration")

            elif self.network_system == "dhcpcd":
                subprocess.run(['systemctl', 'restart', 'dhcpcd'], check=True, timeout=30)
                logger.info("Restarted dhcpcd service")

            elif self.network_system == "interfaces":
                subprocess.run(['systemctl', 'restart', 'networking'], check=True, timeout=30)
                logger.info("Restarted networking service")

            # Wait for network to stabilize
            time.sleep(5)

        except subprocess.TimeoutExpired:
            logger.warning("Network restart timed out")
        except Exception as e:
            logger.error(f"Error restarting networking: {e}")

    def get_current_config(self):
        """Get current network configuration"""
        try:
            interface = self.get_primary_interface()

            # Get IP info using ip command
            result = subprocess.run(['ip', 'addr', 'show', interface],
                                  capture_output=True, text=True, check=True)

            config = {
                'interface': interface,
                'ipType': 'dynamic',  # Default
                'ipAddress': '',
                'subnetMask': '',
                'gateway': '',
                'dnsServer': ''
            }

            # Parse IP address and netmask
            for line in result.stdout.split('\n'):
                if 'inet ' in line and not '127.0.0.1' in line:
                    parts = line.strip().split()
                    for part in parts:
                        if '/' in part and not part.startswith('inet'):
                            ip_cidr = part
                            ip, cidr = ip_cidr.split('/')
                            config['ipAddress'] = ip
                            config['subnetMask'] = self._cidr_to_subnet_mask(int(cidr))
                            break

            # Get gateway
            try:
                result = subprocess.run(['ip', 'route', 'show', 'default'],
                                      capture_output=True, text=True, check=True)
                for line in result.stdout.split('\n'):
                    if 'default' in line:
                        parts = line.split()
                        if 'via' in parts:
                            via_index = parts.index('via')
                            if via_index + 1 < len(parts):
                                config['gateway'] = parts[via_index + 1]
            except:
                pass

            # Get DNS servers
            try:
                with open('/etc/resolv.conf', 'r') as f:
                    for line in f:
                        if line.startswith('nameserver'):
                            config['dnsServer'] = line.split()[1]
                            break
            except:
                pass

            # Determine if static or dynamic
            if self.network_system == "netplan":
                config['ipType'] = self._detect_netplan_type(interface)
            elif self.network_system == "dhcpcd":
                config['ipType'] = self._detect_dhcpcd_type(interface)
            elif self.network_system == "interfaces":
                config['ipType'] = self._detect_interfaces_type(interface)

            return config

        except Exception as e:
            logger.error(f"Error getting current config: {e}")
            return {}

    def _cidr_to_subnet_mask(self, cidr):
        """Convert CIDR to subnet mask"""
        mask = (0xffffffff >> (32 - cidr)) << (32 - cidr)
        return '.'.join([
            str((mask >> 24) & 0xff),
            str((mask >> 16) & 0xff),
            str((mask >> 8) & 0xff),
            str(mask & 0xff)
        ])

    def _detect_netplan_type(self, interface):
        """Detect if netplan config is static or dynamic"""
        try:
            for yaml_file in Path(self.netplan_dir).glob("*.yaml"):
                with open(yaml_file, 'r') as f:
                    import yaml
                    config = yaml.safe_load(f)

                    if 'network' in config and 'ethernets' in config['network']:
                        if interface in config['network']['ethernets']:
                            if 'addresses' in config['network']['ethernets'][interface]:
                                return 'static'
                            elif config['network']['ethernets'][interface].get('dhcp4'):
                                return 'dynamic'
        except:
            pass
        return 'dynamic'

    def _detect_dhcpcd_type(self, interface):
        """Detect if dhcpcd config is static or dynamic"""
        try:
            with open(self.dhcpcd_file, 'r') as f:
                content = f.read()
                if f'interface {interface}' in content and 'static ip_address' in content:
                    return 'static'
        except:
            pass
        return 'dynamic'

    def _detect_interfaces_type(self, interface):
        """Detect if interfaces config is static or dynamic"""
        try:
            with open(self.interfaces_file, 'r') as f:
                content = f.read()
                if f'iface {interface} inet static' in content:
                    return 'static'
                elif f'iface {interface} inet dhcp' in content:
                    return 'dynamic'
        except:
            pass
        return 'dynamic'


# Standalone functions for use in web application
def apply_network_settings(network_config):
    """Apply network settings - main function for web interface"""
    try:
        manager = NetworkManager()
        result = manager.apply_network_config(network_config)
        return result
    except Exception as e:
        logger.error(f"Failed to apply network settings: {e}")
        return {'status': 'error', 'message': f'Network configuration failed: {str(e)}'}

def get_current_network_config():
    """Get current network configuration - main function for web interface"""
    try:
        manager = NetworkManager()
        return manager.get_current_config()
    except Exception as e:
        logger.error(f"Failed to get network config: {e}")
        return {}

if __name__ == "__main__":
    # Test the network manager
    logging.basicConfig(level=logging.INFO)

    manager = NetworkManager()
    current = manager.get_current_config()
    print("Current network configuration:")
    print(json.dumps(current, indent=2))