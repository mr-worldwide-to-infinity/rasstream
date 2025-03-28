#!/bin/bash

# Update en installeer vereisten
echo "Updating system and installing dependencies..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y nodejs npm mpg123 alsa-utils
echo "Installing access point software..."
sudo apt install -y dnsmasq hostapd

# Installeer http-server globaal
echo "Installing http-server..."
sudo npm install -g http-server

# Installeer projectafhankelijkheden
echo "Installing project dependencies..."
cd /home/test/spotify-auth-server
npm install

# Configureer WiFi Access Point
echo "Configuring WiFi Access Point..."
# Deblokkeer WiFi
sudo rfkill unblock all

# Configureer dhcpcd
sudo bash -c 'cat >> /etc/dhcpcd.conf <<EOF
interface wlan0
    static ip_address=192.168.4.1/24
    nohook wpa_supplicant
EOF'

# Configureer dnsmasq
sudo bash -c 'cat > /etc/dnsmasq.conf <<EOF
interface=wlan0
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
bind-interfaces
server=8.8.8.8
EOF'

# Configureer hostapd
sudo bash -c 'cat > /etc/hostapd/hostapd.conf <<EOF
interface=wlan0
driver=nl80211
ssid=RaspberryPiAP
hw_mode=g
channel=7
wmm_enabled=1
ieee80211n=1
auth_algs=1
wpa=2
wpa_passphrase=raspberry
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
country_code=NL
EOF'

sudo bash -c 'cat > /etc/default/hostapd <<EOF
DAEMON_CONF="/etc/hostapd/hostapd.conf"
EOF'

# Maak wifi-check service aan
echo "Creating WiFi check service..."
sudo bash -c 'cat > /etc/systemd/system/wifi-check.service <<EOF
[Unit]
Description=WiFi Connection Check
After=network.target
Before=spotify-auth-server.service http-server.service

[Service]
Type=oneshot
ExecStart=/home/test/wifi-check.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF'

# Maak een service voor de Spotify-auth-server
echo "Creating Spotify Auth Server service..."
sudo bash -c 'cat > /etc/systemd/system/spotify-auth-server.service <<EOF
[Unit]
Description=Spotify Auth Server
After=network.target

[Service]
ExecStart=/usr/bin/node /home/test/spotify-auth-server/server.js
WorkingDirectory=/home/test/spotify-auth-server
Restart=always
User=test
Environment=PORT=3001
EnvironmentFile=/home/test/spotify-auth-server/.env

[Install]
WantedBy=multi-user.target
EOF'

# Maak een service voor de http-server
echo "Creating HTTP Server service..."
sudo bash -c 'cat > /etc/systemd/system/http-server.service <<EOF
[Unit]
Description=HTTP Server for Frontend
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/http-server /home/test -p 5500 --cors
Environment=PATH=/usr/local/bin:/usr/bin:/bin
WorkingDirectory=/home/test
Restart=on-failure
User=test

[Install]
WantedBy=multi-user.target
EOF'

# Zorg ervoor dat wifi-check.sh uitvoerbaar is
echo "Setting up wifi-check script..."
sudo chmod +x /home/test/wifi-check.sh

# Enable services
echo "Enabling services..."
sudo systemctl unmask hostapd
sudo systemctl enable hostapd
sudo systemctl enable dnsmasq
sudo systemctl enable wifi-check.service
sudo systemctl enable spotify-auth-server
sudo systemctl enable http-server

# Start services
echo "Starting services..."
sudo systemctl restart dhcpcd
sudo systemctl start hostapd
sudo systemctl start dnsmasq
sudo systemctl start wifi-check.service
sudo systemctl start spotify-auth-server
sudo systemctl start http-server

echo "Setup complete! The services are running."
echo "Your Raspberry Pi should now appear as 'Raspberry Pi Speaker' in Spotify Connect"

