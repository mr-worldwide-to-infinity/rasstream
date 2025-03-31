#!/bin/bash

# Stop script bij fouten
set -e

# Functie om internet connectiviteit te testen
check_internet() {
    ping -c 1 8.8.8.8 >/dev/null 2>&1
    return $?
}

# Functie om wifi status te controleren
check_wifi_connection() {
    # Check of we een IP hebben op wlan0
    if ip addr show wlan0 | grep -q "inet "; then
        # Check of we verbonden zijn met een SSID
        if iwgetid wlan0 -r > /dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

# Functie om AP mode te starten
start_ap_mode() {
    echo "Starting AP mode..."
    
    # Stop alle netwerk services eerst
    sudo systemctl stop wpa_supplicant
    sudo systemctl stop hostapd
    sudo systemctl stop dnsmasq
    
    # Reset de interface volledig
    sudo ip link set wlan0 down
    sudo ip addr flush dev wlan0
    sudo ip link set wlan0 up
    
    # Wacht even voor de interface
    sleep 2
    
    # Configureer statisch IP
    sudo ip addr add 192.168.4.1/24 dev wlan0
    
    # Start services in de juiste volgorde
    sudo systemctl start hostapd || echo "Failed to start hostapd"
    sleep 2
    sudo systemctl start dnsmasq || echo "Failed to start dnsmasq"
    
    echo "Access point started. SSID: SpotStream"
}

# Hoofdlogica
if check_wifi_connection; then
    if check_internet; then
        echo "Connected to WiFi with internet access: $(iwgetid -r)"
        # Zorg dat AP mode uit staat
        sudo systemctl stop hostapd
        sudo systemctl stop dnsmasq
        # Start wpa_supplicant als die niet al draait
        sudo systemctl start wpa_supplicant
    else
        echo "Connected to WiFi but no internet. Starting AP mode..."
        start_ap_mode
    fi
else
    echo "No WiFi connection. Starting AP mode..."
    start_ap_mode
fi