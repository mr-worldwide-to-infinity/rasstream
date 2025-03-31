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
async function getCurrentIP() {
    return new Promise((resolve) => {
        exec('ip -f inet addr show wlan0 | grep -Po "(?<=inet )([0-9.]+)"', (error, stdout) => {
            if (error || !stdout.trim()) {
                resolve('192.168.4.1'); // Fallback naar AP IP
            } else {
                resolve(stdout.trim());
            }
        });
    });
}

// 🔹 1. Route om gebruiker naar Spotify login te sturen
app.get('/login', async (req, res) => {
    const currentIP = await getCurrentIP();
    const redirectUri = `http://${currentIP}:${PORT}/callback`;
    
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
    const currentIP = await getCurrentIP();
    const redirectUri = `http://${currentIP}:${PORT}/callback`;

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
        res.redirect(`http://${currentIP}:5500/test.html`);
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
app.get('/status', (req, res) => {
    // Helper functie om commands uit te voeren
    const execPromise = (command) => {
        return new Promise((resolve, reject) => {
            exec(command, (error, stdout, stderr) => {
                if (error) reject(error);
                else resolve(stdout.trim());
            });
        });
    };

    // Check alle netwerk informatie
    async function checkNetworkStatus() {
        try {
            // Check AP mode
            const hostapd = await execPromise('sudo systemctl is-active hostapd');
            const isAPMode = hostapd === 'active';

            if (isAPMode) {
                const apIP = await execPromise('ip -f inet addr show wlan0 | grep -Po "(?<=inet )([0-9.]+)"');
                return res.json({ 
                    connected: true,
                    mode: 'AP',
                    ip: apIP,
                    message: 'Running in Access Point mode'
                });
            }

            // Check client mode
            const iwconfig = await execPromise('iwconfig wlan0');
            if (iwconfig.includes('ESSID:off/any')) {
                return res.json({ 
                    connected: false,
                    mode: 'client',
                    message: 'Not connected to any network'
                });
            }

            // Get network details
            const ssid = await execPromise('iwgetid -r');
            const ip = await execPromise('ip -f inet addr show wlan0 | grep -Po "(?<=inet )([0-9.]+)"');
            
            // Check internet
            let hasInternet = false;
            try {
                await execPromise('ping -c 1 -W 1 8.8.8.8');
                hasInternet = true;
            } catch (error) {
                hasInternet = false;
            }

            return res.json({
                connected: true,
                mode: 'client',
                ssid: ssid,
                ip: ip,
                internet: hasInternet
            });

        } catch (error) {
            console.error('Error checking network status:', error);
            return res.json({ 
                connected: false,
                mode: 'unknown',
                error: 'Failed to check connection status',
                details: error.message
            });
        }
    }

    // Voer de check uit
    checkNetworkStatus().catch(error => {
        console.error('Status check failed:', error);
        res.status(500).json({ 
            error: 'Status check failed', 
            details: error.message 
        });
    });
});

// 🔹 Endpoint om beschikbare WiFi-netwerken te scannen
app.get('/networks', (req, res) => {
    // Check eerst of we in AP mode zijn
    exec('systemctl is-active hostapd', (error, apStdout) => {
        const isAPMode = apStdout.trim() === 'active';
        
        if (!isAPMode) {
            return res.status(400).json({ 
                error: 'Must be in AP mode to scan networks',
                message: 'Currently connected to a network. Disconnect first to scan.'
            });
        }

        exec('iwlist wlan0 scan', (error, stdout) => {
            if (error) {
                console.error('Error scanning networks:', error);
                return res.status(500).json({ error: 'Error scanning networks' });
            }

            const networks = [];
            const lines = stdout.split('\n');
            let currentNetwork = {};

            lines.forEach(line => {
                line = line.trim();
                
                if (line.startsWith('Cell')) {
                    if (currentNetwork.ssid) {
                        networks.push(currentNetwork);
                    }
                    currentNetwork = {};
                }
                
                if (line.startsWith('ESSID:')) {
                    const ssid = line.match(/ESSID:"(.*)"/)?.[1];
                    if (ssid) {
                        currentNetwork.ssid = ssid;
                    }
                }
                
                if (line.includes('Signal level=')) {
                    const signal = line.match(/Signal level=(-\d+)/)?.[1];
                    if (signal) {
                        currentNetwork.signal = parseInt(signal);
                    }
                }
            });

            if (currentNetwork.ssid) {
                networks.push(currentNetwork);
            }

            // Sorteer op signaalsterkte
            networks.sort((a, b) => (b.signal || -100) - (a.signal || -100));

            res.json(networks);
        });
    });
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
