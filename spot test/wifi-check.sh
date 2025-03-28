#!/bin/bash

# Stop script bij fouten
set -e

# Voeg toe voor de AP configuratie:
# Zorg dat hostapd niet al draait
sudo systemctl stop hostapd

# Functie om internet connectiviteit te testen
check_internet() {
    ping -c 1 8.8.8.8 >/dev/null 2>&1
    return $?
}

# Functie om normale WiFi-modus te herstellen
restore_wifi_mode() {
    echo "Herstellen normale WiFi-modus..."
    sudo systemctl stop hostapd
    sudo systemctl stop dnsmasq
    sudo ip addr flush dev wlan0
    sudo systemctl start wpa_supplicant
    sudo systemctl restart dhcpcd5
    # Wacht even tot de verbinding is hersteld
    sleep 5
}

# Controleer of er een actieve WiFi-verbinding én internet is
if ! check_internet; then
    echo "Geen internet verbinding gevonden. Start access point..."

    # Stop eventuele bestaande services
    sudo systemctl stop wpa_supplicant
    
    # Configureer een statisch IP-adres
    sudo ifconfig wlan0 192.168.4.1

    # Start dnsmasq
    sudo bash -c 'cat > /etc/dnsmasq.conf <<EOF
interface=wlan0
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
EOF'
    sudo systemctl restart dnsmasq

    # Configureer hostapd met verbeterde instellingen voor Pi 3 B+
    sudo bash -c 'cat > /etc/hostapd/hostapd.conf <<EOF
interface=wlan0
driver=nl80211
ssid=RaspberryPiAP
hw_mode=g
channel=7
wmm_enabled=1
ieee80211n=1
ht_capab=[HT40][SHORT-GI-20][DSSS_CCK-40]
country_code=NL
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=raspberry
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF'
    sudo bash -c 'echo "DAEMON_CONF=\"/etc/hostapd/hostapd.conf\"" > /etc/default/hostapd'
    sudo systemctl unmask hostapd
    sudo systemctl enable hostapd
    sudo systemctl start hostapd

    echo "Access point gestart. Verbinden met SSID: RaspberryPiAP, wachtwoord: raspberry"
    echo "Ga naar http://192.168.4.1:5500 om WiFi te configureren"
else
    echo "Internet verbinding gevonden: $(iwgetid -r)"
    restore_wifi_mode
fi