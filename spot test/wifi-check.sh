#!/bin/bash

# Controleer of er een actieve WiFi-verbinding is
if ! iwgetid -r > /dev/null; then
    echo "Geen WiFi-verbinding gevonden. Start access point..."

    # Configureer een statisch IP-adres
    sudo ifconfig wlan0 192.168.4.1

    # Start dnsmasq
    sudo bash -c 'cat > /etc/dnsmasq.conf <<EOF
interface=wlan0
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
EOF'
    sudo systemctl restart dnsmasq

    # Configureer hostapd
    sudo bash -c 'cat > /etc/hostapd/hostapd.conf <<EOF
interface=wlan0
driver=nl80211
ssid=RaspberryPiAP
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=raspberry
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF'
    sudo bash -c 'echo "DAEMON_CONF=\"/etc/hostapd/hostapd.conf\"" > /etc/default/hostapd'
    sudo systemctl start hostapd

    echo "Access point gestart. Verbinden met SSID: RaspberryPiAP, wachtwoord: raspberry"
else
    echo "WiFi-verbinding gevonden: $(iwgetid -r)"
fi