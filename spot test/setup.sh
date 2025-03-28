#!/bin/bash

# Update en installeer vereisten
echo "Updating system and installing dependencies..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y nodejs npm mpg123

# Installeer http-server globaal
echo "Installing http-server..."
sudo npm install -g http-server

# Installeer projectafhankelijkheden
echo "Installing project dependencies..."
cd /home/test/spotify-auth-server
npm install

# Installeer Librespot (Spotify Connect client)
echo "Installing Librespot..."
curl -sL https://dtcooper.github.io/raspotify/install.sh | sh

# Configureer Librespot
echo "Configuring Librespot..."
sudo bash -c 'cat > /etc/raspotify/conf <<EOF
LIBRESPOT_NAME="Raspberry Pi Speaker"
LIBRESPOT_BACKEND="alsa"
LIBRESPOT_DEVICE="default:CARD=0"
LIBRESPOT_INITIAL_VOLUME="100"
EOF'

# Start en enable Raspotify service
echo "Starting Raspotify service..."
sudo systemctl enable raspotify
sudo systemctl restart raspotify

# Maak WiFi setup script
echo "Creating WiFi setup script..."
sudo bash -c 'cat > /home/test/setup-wifi.sh << '\''EOF'\''
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
EOF'

# Zet de juiste rechten voor het WiFi script
echo "Setting permissions for WiFi setup script..."
sudo chmod +x /home/test/setup-wifi.sh
sudo chown test:test /home/test/setup-wifi.sh

# Configureer sudo rechten voor WiFi setup
echo "Configuring sudo permissions for WiFi..."
sudo bash -c 'echo "test ALL=(ALL) NOPASSWD: /usr/sbin/wpa_cli" > /etc/sudoers.d/wifi-permissions'
sudo bash -c 'echo "test ALL=(ALL) NOPASSWD: /bin/tee -a /etc/wpa_supplicant/wpa_supplicant.conf" >> /etc/sudoers.d/wifi-permissions'
sudo chmod 440 /etc/sudoers.d/wifi-permissions

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
StartLimitIntervalSec=500
StartLimitBurst=5

[Service]
Type=simple
ExecStart=/usr/local/bin/http-server /home/test -p 5500 --cors
Environment=PATH=/usr/local/bin:/usr/bin:/bin
WorkingDirectory=/home/test
Restart=on-failure
RestartSec=5s
User=test
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF'

# Update het pad in de wifi-check service
sudo bash -c 'cat > /etc/systemd/system/wifi-check.service <<EOF
[Unit]
Description=WiFi Check and Access Point Setup
After=network.target

[Service]
ExecStart=/bin/bash /home/test/wifi-check.sh
Restart=always
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

# Installeer WiFi tools
sudo apt install -y wireless-tools
sudo apt install -y hostapd dnsmasq
sudo systemctl stop hostapd
sudo systemctl stop dnsmasq

# Enable en start wifi-check
sudo systemctl enable wifi-check
sudo systemctl start wifi-check

# Check services status
echo "Checking service status..."
echo "Spotify Auth Server status:"
sudo systemctl status spotify-auth-server
echo "HTTP Server status:"
sudo systemctl status http-server
echo "Raspotify status:"
sudo systemctl status raspotify
echo "WiFi Check status:"
sudo systemctl status wifi-check

# Installeer audio dependencies
echo "Installing audio dependencies..."
sudo apt install -y alsa-utils

# Test audio setup
echo "Testing audio setup..."
aplay -l

echo "Setup complete! The services are running."
echo "Your Raspberry Pi should now appear as 'Raspberry Pi Speaker' in Spotify Connect"
echo "Check the status of Raspotify with: sudo systemctl status raspotify"

# Herstart de server
sudo systemctl restart spotify-auth-server