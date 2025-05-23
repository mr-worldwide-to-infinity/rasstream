#!/bin/bash

# Update en installeer vereisten eerst
echo "Updating system and installing dependencies..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y nodejs npm mpg123 alsa-utils avahi-daemon dnsmasq hostapd network-manager

# Stel hostname in
echo "Setting hostname..."
sudo hostnamectl set-hostname spotStream
sudo sed -i 's/127.0.1.1.*raspberrypi/127.0.1.1\tspotStream/g' /etc/hosts

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
sudo bash -c 'cat > /etc/dhcpcd.conf <<EOF
# Standaard configuratie
hostname
clientid
persistent
option rapid_commit
option domain_name_servers, domain_name, domain_search, host_name
option classless_static_routes
option interface_mtu
require dhcp_server_identifier
slaac private

# AP mode configuratie
interface wlan0
    nohook wpa_supplicant
EOF'

# Configureer dnsmasq
sudo bash -c 'cat > /etc/dnsmasq.conf <<EOF
interface=wlan0
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
bind-interfaces
server=8.8.8.8
dhcp-option=3,192.168.4.1
dhcp-option=6,192.168.4.1
EOF'

# Configureer hostapd
sudo bash -c 'cat > /etc/hostapd/hostapd.conf <<EOF
interface=wlan0
driver=nl80211
ssid=SpotStream
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
After=network-online.target
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
After=network-online.target wifi-check.service
Wants=network-online.target

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
After=network-online.target wifi-check.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/http-server /home/test -p 3001 --cors -a 0.0.0.0
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
sudo systemctl daemon-reload
sudo systemctl enable avahi-daemon
sudo systemctl enable hostapd
sudo systemctl enable dnsmasq
sudo systemctl enable wifi-check.service
sudo systemctl enable spotify-auth-server
sudo systemctl enable http-server

# Start services in de juiste volgorde
echo "Starting services..."
sudo systemctl restart avahi-daemon
sudo systemctl restart dhcpcd
sudo systemctl restart hostapd
sudo systemctl restart dnsmasq
sudo systemctl restart wifi-check
sudo systemctl restart spotify-auth-server
sudo systemctl restart http-server

echo "Setup complete! The services are running."
echo "Your Raspberry Pi should now appear as SpotStream"

# Maak toggle-wifi-mode script
sudo bash -c 'cat > /home/test/toggle-wifi-mode.sh <<EOF
#!/bin/bash

function start_ap_mode() {
    sudo ip addr flush dev wlan0
    sudo ip addr add 192.168.4.1/24 dev wlan0
    sudo systemctl start hostapd
    sudo systemctl start dnsmasq
}

function start_client_mode() {
    sudo ip addr flush dev wlan0
    sudo dhclient -r wlan0
    sudo dhclient wlan0
}

case "$1" in
    "ap")
        start_ap_mode
        ;;
    "client")
        start_client_mode
        ;;
esac
EOF'

sudo chmod +x /home/test/toggle-wifi-mode.sh

# Enable and start NetworkManager
sudo systemctl enable NetworkManager
sudo systemctl start NetworkManager

# Configure NetworkManager to manage wlan0
sudo bash -c 'cat > /etc/NetworkManager/conf.d/10-globally-managed-devices.conf' << EOF
[keyfile]
unmanaged-devices=none
EOF

# Restart NetworkManager to apply changes
sudo systemctl restart NetworkManager

