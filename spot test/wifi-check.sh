#!/bin/bash

# Stop script bij fouten
set -e

# Functie om internet connectiviteit te testen
check_internet() {
    ping -c 1 8.8.8.8 >/dev/null 2>&1
    return $?
}

# Functie om AP mode te starten
start_ap_mode() {
    echo "Starting AP mode..."
    
    # Stop bestaande services
    sudo systemctl stop wpa_supplicant
    sudo systemctl stop hostapd
    sudo systemctl stop dnsmasq
    
    # Reset de interface
    sudo ip link set wlan0 down
    sudo ip addr flush dev wlan0
    sudo ip link set wlan0 up
    
    # Configureer statisch IP
    sudo ip addr add 192.168.4.1/24 dev wlan0
    
    # Start AP services
    sudo systemctl start hostapd
    sudo systemctl start dnsmasq
    
    echo "Access point started. SSID: RaspberryPiAP, Password: raspberry"
}

# Controleer of er een actieve WiFi-verbinding én internet is
if ! check_internet; then
    echo "No internet connection found. Starting access point..."
    start_ap_mode
else
    echo "Internet connection found: $(iwgetid -r)"
    # Zorg dat we in client mode blijven
    sudo systemctl stop hostapd
    sudo systemctl stop dnsmasq
    sudo systemctl start wpa_supplicant
fi