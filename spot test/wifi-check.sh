#!/bin/bash

# Logging functie
log() {
    echo "$(date): $1"
    logger -t wifi-check "$1"
}

# Functie om internet connectiviteit te testen
check_internet() {
    for i in {1..3}; do
        if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}

# Functie om wifi status te controleren
check_wifi_connection() {
    local SSID=$(sudo iwgetid wlan0 -r 2>/dev/null)
    local IP=$(sudo ip -f inet addr show wlan0 | grep -Po "(?<=inet )([0-9.]+)" 2>/dev/null)
    
    if [ -n "$IP" ] && [ -n "$SSID" ]; then
        log "Connected to SSID: $SSID with IP: $IP"
        return 0
    fi
    log "No valid WiFi connection found"
    return 1
}

# Functie om AP mode te starten
start_ap_mode() {
    log "Starting AP mode..."
    
    sudo systemctl stop wpa_supplicant
    sudo systemctl stop hostapd
    sudo systemctl stop dnsmasq
    
    # Reset de interface volledig
    sudo ip link set wlan0 down
    sudo ip addr flush dev wlan0
    sudo ip link set wlan0 up
    
    # Wacht even voor de interface
    sleep 10
    
    # Configureer statisch IP
    sudo ip addr add 192.168.4.1/24 dev wlan0
    
    # Start services in de juiste volgorde
    sudo systemctl start hostapd || log "Failed to start hostapd"
    sleep 10
    sudo systemctl start dnsmasq || log "Failed to start dnsmasq"
    
    log "AP mode started"
}

# Functie om AP mode te stoppen
stop_ap_mode() {
    log "Stopping AP mode..."
    sudo systemctl stop hostapd
    sudo systemctl stop dnsmasq
    sudo ip addr flush dev wlan0
    sudo systemctl restart wpa_supplicant
    log "AP mode stopped"
}

# Hoofdlogica
log "Starting WiFi check..."

if check_wifi_connection; then
    if check_internet; then
        log "Internet connection verified"
        if sudo systemctl is-active --quiet hostapd; then
            stop_ap_mode
        fi
    else
        log "No internet connection"
        start_ap_mode
    fi
else
    log "No WiFi connection"
    start_ap_mode
fi

# Schrijf de huidige status naar een bestand
CURRENT_SSID=$(sudo iwgetid wlan0 -r 2>/dev/null || echo "")
CURRENT_IP=$(sudo ip -f inet addr show wlan0 | grep -Po "(?<=inet )([0-9.]+)" 2>/dev/null || echo "")
IS_AP_MODE=$(sudo systemctl is-active hostapd)

sudo bash -c "cat > /tmp/wifi_status" <<EOF
SSID=$CURRENT_SSID
IP=$CURRENT_IP
AP_MODE=$IS_AP_MODE
EOF

log "WiFi check completed"