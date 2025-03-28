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

# Start en activeer de services
echo "Starting and enabling services..."
sudo systemctl daemon-reload
sudo systemctl enable wifi-check.service
sudo systemctl enable spotify-auth-server
sudo systemctl enable http-server
sudo systemctl start wifi-check.service
sudo systemctl start spotify-auth-server
sudo systemctl start http-server

echo "Setup complete! The services are running."
echo "Your Raspberry Pi should now appear as 'Raspberry Pi Speaker' in Spotify Connect"

