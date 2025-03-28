#!/bin/bash

# Update en installeer vereisten
echo "Updating system and installing dependencies..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y nodejs npm mpg123 alsa-utils

# Installeer http-server globaal
echo "Installing http-server..."
sudo npm install -g http-server

# Installeer projectafhankelijkheden
echo "Installing project dependencies..."
cd /home/test/spotify-auth-server
npm install

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

# Start en activeer de services
echo "Starting and enabling services..."
sudo systemctl daemon-reload
sudo systemctl enable spotify-auth-server
sudo systemctl enable http-server
sudo systemctl start spotify-auth-server
sudo systemctl start http-server

echo "Setup complete! The services are running."
echo "Your Raspberry Pi should now appear as 'Raspberry Pi Speaker' in Spotify Connect"

# Configureer vast IP-adres
echo "Configuring static IP address..."
sudo bash -c 'cat >> /etc/dhcpcd.conf <<EOF

# Configuratie voor vast IP-adres
interface wlan0
static ip_address=192.168.4.1/24
nohook wpa_supplicant
EOF'

# Installeer access point software
echo "Installing access point software..."
sudo apt install -y dnsmasq hostapd

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
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF'

# Configureer dnsmasq
sudo bash -c 'cat > /etc/dnsmasq.conf <<EOF
interface=wlan0
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
EOF'

# Enable hostapd
sudo systemctl unmask hostapd
sudo systemctl enable hostapd

# Start services
sudo systemctl restart dhcpcd
sudo systemctl restart hostapd
sudo systemctl restart dnsmasq

# Maak een script voor het configureren van de access point interface
sudo bash -c 'cat > /usr/local/bin/create-ap-interface.sh <<EOF
#!/bin/bash
iw phy phy0 interface add uap0 type __ap
ip link set uap0 up
EOF'
sudo chmod +x /usr/local/bin/create-ap-interface.sh

# Configureer vast IP-adres voor access point interface
sudo bash -c 'cat >> /etc/dhcpcd.conf <<EOF

# Configuratie voor access point interface
interface uap0
static ip_address=192.168.4.1/24
nohook wpa_supplicant
EOF'

# Configureer hostapd voor de access point interface
sudo bash -c 'cat > /etc/hostapd/hostapd.conf <<EOF
interface=uap0
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
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF'

# Configureer dnsmasq voor DHCP op access point interface
sudo bash -c 'cat > /etc/dnsmasq.conf <<EOF
interface=uap0
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
EOF'

# Maak een systemd service voor het aanmaken van de AP interface
sudo bash -c 'cat > /etc/systemd/system/create-ap-interface.service <<EOF
[Unit]
Description=Create AP interface
Before=hostapd.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/create-ap-interface.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF'

# Enable services
sudo systemctl enable create-ap-interface
sudo systemctl enable hostapd