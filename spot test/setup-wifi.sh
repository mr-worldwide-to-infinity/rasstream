#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

SSID="$1"
PSK="$2"

if [ -z "$SSID" ]; then
    echo "SSID is required"
    exit 1
fi

# Backup existing configuration
cp /etc/wpa_supplicant/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant.conf.backup

# Create new network configuration
cat > /etc/wpa_supplicant/wpa_supplicant.conf << EOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=NL

network={
    ssid="$SSID"
    psk="$PSK"
    key_mgmt=WPA-PSK
}
EOF

# Set correct permissions
chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf

# Restart networking
wpa_cli -i wlan0 reconfigure

# Wait a bit for the connection
sleep 5

# Check if we got an IP address
if ip addr show wlan0 | grep -q "inet "; then
    echo "Successfully connected to WiFi network"
    exit 0
else
    echo "Failed to connect to WiFi network"
    # Restore backup
    cp /etc/wpa_supplicant/wpa_supplicant.conf.backup /etc/wpa_supplicant/wpa_supplicant.conf
    exit 1
fi 