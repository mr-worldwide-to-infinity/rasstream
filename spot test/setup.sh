#!/bin/bash

# Update en installeer vereisten
echo "Updating system and installing dependencies..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y nodejs npm

# Installeer http-server globaal
echo "Installing http-server..."
sudo npm install -g http-server

# Installeer projectafhankelijkheden
echo "Installing project dependencies..."
cd spotify-auth-server
npm install

# Maak een service voor de Spotify-auth-server
echo "Creating Spotify Auth Server service..."
sudo bash -c 'cat > /etc/systemd/system/spotify-auth-server.service <<EOF
[Unit]
Description=Spotify Auth Server
After=network.target

[Service]
ExecStart=/usr/bin/node /home/pi/spotify-auth-server/server.js
WorkingDirectory=/home/pi/spotify-auth-server
Restart=always
User=pi
Environment=PORT=3001
EnvironmentFile=/home/pi/spotify-auth-server/.env

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
ExecStart=/usr/bin/http-server /home/pi -p 5500
WorkingDirectory=/home/pi
Restart=always
User=pi

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
sudo apt install -y wireless-tools
sudo apt install -y hostapd dnsmasq
sudo systemctl stop hostapd
sudo systemctl stop dnsmasq
sudo bash -c 'cat > /etc/systemd/system/wifi-check.service <<EOF
[Unit]
Description=WiFi Check and Access Point Setup
After=network.target

[Service]
ExecStart=/bin/bash /home/pi/wifi-check.sh
Restart=always
User=pi

[Install]
WantedBy=multi-user.target
EOF'

sudo systemctl enable wifi-check
sudo systemctl start wifi-check

echo "Setup complete! The server is running."