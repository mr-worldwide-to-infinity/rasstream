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

# Check welke processen poort 3001 gebruiken
sudo lsof -i :3001

# Check welke processen poort 5500 gebruiken
sudo lsof -i :5500

# Check de logs van elke service
sudo journalctl -u spotify-auth-server -n 50
sudo journalctl -u http-server -n 50
sudo journalctl -u wifi-check -n 50

# Reset alle services
sudo systemctl reset-failed
sudo systemctl daemon-reload
sudo systemctl stop spotify-auth-server
sudo systemctl stop http-server
sudo systemctl stop wifi-check

# Debug commando's
echo "Checking permissions..."
ls -l /home/test/spotify-auth-server/server.js
ls -l /home/test/wifi-check.sh

echo "Checking Node.js installation..."
which node
node --version

echo "Checking if ports are already in use..."
sudo netstat -tulpn | grep -E ':3001|:5500'

echo "Starting services with verbose logging..."
sudo systemctl start spotify-auth-server --no-block
sudo systemctl start http-server --no-block
sudo systemctl start wifi-check --no-block

echo "Waiting for services to start..."
sleep 5

echo "Checking service status..."
sudo systemctl status spotify-auth-server
sudo systemctl status http-server
sudo systemctl status wifi-check

echo "Checking logs..."
sudo journalctl -xe

echo "Setup complete! The server is running."