require('dotenv').config();
const express = require('express');
const axios = require('axios');
const cors = require('cors');
const cookieParser = require('cookie-parser');
const querystring = require('querystring');
const { exec, spawn } = require('child_process');
const fs = require('fs');

const app = express();
const PORT = process.env.PORT || 3001;

// Vervang de bestaande CORS configuratie
app.use(cors({
    origin: function(origin, callback) {
        // Accept requests from any origin during development
        callback(null, true);
    },
    credentials: true
}));
app.use(express.json());
app.use(cookieParser());

const SPOTIFY_AUTH_URL = 'https://accounts.spotify.com/authorize';
const SPOTIFY_TOKEN_URL = 'https://accounts.spotify.com/api/token';

// Globale variabele om het radio proces bij te houden
let radioProcess = null;

// Voeg deze helper functie toe bovenaan het bestand na de imports
async function getServerUrl() {
    return 'spotStream.local';
}

// 🔹 1. Route om gebruiker naar Spotify login te sturen
app.get('/login', async (req, res) => {
    const hostname = await getServerUrl();
    const redirectUri = `http://${hostname}:${PORT}/callback`;
    
    const scope = 'streaming user-read-email user-read-private user-read-playback-state user-modify-playback-state app-remote-control';
    const queryParams = querystring.stringify({
        response_type: 'code',
        client_id: process.env.SPOTIFY_CLIENT_ID,
        scope: scope,
        redirect_uri: redirectUri,
    });

    res.redirect(`${SPOTIFY_AUTH_URL}?${queryParams}`);
});

// 🔹 2. Spotify callback route
app.get('/callback', async (req, res) => {
    const code = req.query.code;
    const hostname = await getServerUrl();
    const redirectUri = `http://${hostname}:${PORT}/callback`;

    try {
        const response = await axios.post(SPOTIFY_TOKEN_URL, new URLSearchParams({
            grant_type: 'authorization_code',
            code: code,
            redirect_uri: redirectUri,
            client_id: process.env.SPOTIFY_CLIENT_ID,
            client_secret: process.env.SPOTIFY_CLIENT_SECRET,
        }), {
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        });

        res.cookie('access_token', response.data.access_token, {
            httpOnly: true,
            secure: false,
            sameSite: 'lax',
            maxAge: 3600000 // 1 hour
        });
        
        res.cookie('refresh_token', response.data.refresh_token, {
            httpOnly: true,
            secure: false,
            sameSite: 'lax',
            maxAge: 30 * 24 * 3600000 // 30 days
        });

        // Gebruik hetzelfde IP voor de redirect
        res.redirect(`http://${hostname}:5500/test.html`);
    } catch (error) {
        console.error("Error getting token:", error.response?.data || error.message);
        res.status(500).send("Authentication failed");
    }
});

// 🔹 3. Token refresh route
app.post('/refresh-token', async (req, res) => {
    const refresh_token = req.cookies.refresh_token;
    
    if (!refresh_token) {
        return res.status(401).json({ error: 'No refresh token' });
    }

    try {
        const response = await axios.post(SPOTIFY_TOKEN_URL, new URLSearchParams({
            grant_type: 'refresh_token',
            refresh_token: refresh_token,
            client_id: process.env.SPOTIFY_CLIENT_ID,
            client_secret: process.env.SPOTIFY_CLIENT_SECRET,
        }), {
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        });

        res.cookie('access_token', response.data.access_token, {
            httpOnly: true,
            secure: false,
            sameSite: 'lax',
            maxAge: 3600000
        });

        res.json({ success: true });
    } catch (error) {
        console.error("Error refreshing token:", error.response?.data || error.message);
        res.status(500).json({ error: 'Failed to refresh token' });
    }
});

// Voeg een route toe om token status te checken
app.get('/check-token', (req, res) => {
    const access_token = req.cookies.access_token;
    const refresh_token = req.cookies.refresh_token;
    res.json({
        hasAccessToken: !!access_token,
        hasRefreshToken: !!refresh_token
    });
});

// 🔹 Endpoint om de verbindingsstatus te controleren
app.get('/status', async (req, res) => {
    const execPromise = (command) => {
        return new Promise((resolve, reject) => {
            exec(`sudo ${command}`, (error, stdout, stderr) => {
                if (error) {
                    console.log(`Command failed: ${command}`, error);
                    resolve('inactive'); // Return inactive instead of rejecting
                } else {
                    resolve(stdout.trim());
                }
            });
        });
    };

    try {
        // Check eerst of hostapd actief is
        const hostapdStatus = await execPromise('systemctl is-active hostapd');
        const isAPMode = hostapdStatus === 'active';

        // Haal IP adres op een meer directe manier
        let ipAddress;
        try {
            const ipOutput = await execPromise('ip -4 addr show wlan0');
            const ipMatch = ipOutput.match(/inet\s+(\d+\.\d+\.\d+\.\d+)/);
            ipAddress = ipMatch ? ipMatch[1] : null;
            console.log('Found IP:', ipAddress);
        } catch (err) {
            console.error('Error getting IP:', err);
            ipAddress = null;
        }

        if (isAPMode) {
            return res.json({
                connected: true,
                mode: 'AP',
                ip: ipAddress || '192.168.4.1',
                message: 'Running in Access Point mode (SpotStream)\nConnect to this network to configure WiFi'
            });
        }

        // Gebruik nmcli voor WiFi status
        const wifiStatus = await execPromise('nmcli -t -f DEVICE,STATE,CONNECTION dev | grep wlan0');
        console.log('WiFi status:', wifiStatus);

        if (wifiStatus.includes('connected')) {
            // Haal SSID op via nmcli
            const ssid = await execPromise('nmcli -t -f NAME connection show --active | head -n1');
            const hasInternet = await execPromise('ping -c 1 -W 2 8.8.8.8').then(() => true).catch(() => false);
            
            return res.json({
                connected: true,
                mode: 'client',
                ssid: ssid,
                ip: ipAddress,
                internet: hasInternet
            });
        }

        return res.json({
            connected: false,
            mode: 'client',
            message: 'Not connected to any network',
            ip: ipAddress
        });

    } catch (error) {
        console.error('Error checking status:', error);
        // Return a more informative error response
        res.status(500).json({
            error: 'Failed to check status',
            details: error.message,
            connected: false,
            mode: 'unknown'
        });
    }
});

// 🔹 Endpoint om beschikbare WiFi-netwerken te scannen
app.get('/networks', async (req, res) => {
    try {
        // Check eerst of we in AP mode zijn
        const hostapdStatus = await exec('sudo systemctl is-active hostapd');
        const isAPMode = hostapdStatus.trim() === 'active';
        
        if (!isAPMode) {
            return res.status(400).json({ 
                error: 'Must be in AP mode to scan networks',
                message: 'Currently connected to a network. Disconnect first to scan.'
            });
        }

        // Scan voor netwerken met nmcli
        exec('sudo nmcli -f SSID,SIGNAL dev wifi list', (error, stdout) => {
            if (error) {
                console.error('Error scanning networks:', error);
                return res.status(500).json({ error: 'Error scanning networks' });
            }

            const networks = stdout
                .split('\n')
                .slice(1) // Skip header row
                .filter(line => line.trim()) // Remove empty lines
                .map(line => {
                    const [ssid, signal] = line.trim().split(/\s+/);
                    return {
                        ssid: ssid,
                        signal: parseInt(signal) || 0
                    };
                })
                .filter(network => network.ssid !== '--'); // Filter out networks without SSID

            // Sorteer op signaalsterkte
            networks.sort((a, b) => b.signal - a.signal);

            res.json(networks);
        });
    } catch (error) {
        console.error('Error in networks endpoint:', error);
        res.status(500).json({ error: 'Failed to scan networks' });
    }
});

// 🔹 Endpoint om verbinding te maken met een WiFi-netwerk
app.post('/connect', (req, res) => {
    const { ssid, password } = req.body;

    if (!ssid) {
        return res.status(400).json({ error: 'SSID is required' });
    }

    console.log('Attempting to connect to WiFi:', ssid);

    // Stop eerst de AP mode
    exec('sudo systemctl stop hostapd', (error) => {
        if (error) {
            console.error('Error stopping hostapd:', error);
            return res.status(500).json({ error: 'Error stopping AP mode' });
        }

        // Gebruik raspi-config om WiFi in te stellen
        exec(`sudo raspi-config nonint do_wifi_ssid_passphrase "${ssid}" "${password}"`, (error) => {
            if (error) {
                console.error('Error setting WiFi:', error);
                // Start AP mode weer bij error
                exec('sudo systemctl start hostapd');
                return res.status(500).json({ error: 'Error setting WiFi configuration' });
            }

            // Wacht en check de verbinding
            setTimeout(() => {
                exec('iwgetid -r', (error, stdout) => {
                    if (error || !stdout.trim() || stdout.trim() !== ssid) {
                        console.error('Failed to connect to WiFi');
                        // Start AP mode weer als verbinding mislukt
                        exec('sudo systemctl start hostapd');
                        return res.status(500).json({ error: 'Failed to connect to WiFi' });
                    }

                    // Check internet connectivity
                    exec('ping -c 1 8.8.8.8', (error) => {
                        if (error) {
                            console.error('No internet connectivity');
                            // Start AP mode weer als geen internet
                            exec('sudo systemctl start hostapd');
                            return res.status(500).json({ error: 'No internet connectivity' });
                        }

                        res.json({ success: true });
                    });
                });
            }, 10000);
        });
    });
});

// 🔹 4. Radio control routes
app.post('/radio/play', (req, res) => {
    const { station } = req.body;
    
    if (radioProcess) {
        radioProcess.kill();
        radioProcess = null;
    }

    let streamUrl;
    switch(station) {
        case 'radio1':
            streamUrl = 'http://icecast.omroep.nl/radio1-bb-mp3';
            break;
        case 'radio4':
            streamUrl = 'http://icecast.omroep.nl/radio4-bb-mp3';
            break;
        default:
            return res.status(400).json({ error: 'Invalid station' });
    }

    radioProcess = spawn('mpg123', ['-o', 'alsa', '--no-control', streamUrl]);
    
    radioProcess.on('error', (error) => {
        console.error('Error playing radio:', error);
        res.status(500).json({ error: 'Failed to play radio' });
    });

    res.json({ success: true });
});

app.post('/radio/stop', (req, res) => {
    if (radioProcess) {
        radioProcess.kill();
        radioProcess = null;
    }
    res.json({ success: true });
});

// 🔹 5. Start de server
app.listen(PORT, '0.0.0.0', () => {
    console.log(`Server draait op poort ${PORT}`);
});
