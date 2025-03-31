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

app.use(cors({ origin: process.env.FRONTEND_URL, credentials: true }));
app.use(express.json());
app.use(cookieParser());

const SPOTIFY_AUTH_URL = 'https://accounts.spotify.com/authorize';
const SPOTIFY_TOKEN_URL = 'https://accounts.spotify.com/api/token';

// Globale variabele om het radio proces bij te houden
let radioProcess = null;

// 🔹 1. Route om gebruiker naar Spotify login te sturen
app.get('/login', (req, res) => {
    const scope = 'streaming user-read-email user-read-private user-read-playback-state user-modify-playback-state app-remote-control';
    const queryParams = querystring.stringify({
        response_type: 'code',
        client_id: process.env.SPOTIFY_CLIENT_ID,
        scope: scope,
        redirect_uri: process.env.REDIRECT_URI,
    });

    res.redirect(`${SPOTIFY_AUTH_URL}?${queryParams}`);
});

// 🔹 2. Spotify callback route
app.get('/callback', async (req, res) => {
    const code = req.query.code;

    try {
        const response = await axios.post(SPOTIFY_TOKEN_URL, new URLSearchParams({
            grant_type: 'authorization_code',
            code: code,
            redirect_uri: process.env.REDIRECT_URI,
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

        res.redirect(`${process.env.FRONTEND_URL}/test.html`);
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

// 🔹 Endpoint om beschikbare WiFi-netwerken te scannen
app.get('/networks', (req, res) => {
    exec('iwlist wlan0 scan', (error, stdout) => {
        if (error) {
            console.error('Error scanning networks:', error);
            return res.status(500).json({ error: 'Error scanning networks' });
        }

        const networks = [];
        const regex = /ESSID:"(.*?)"/g;
        let match;
        while ((match = regex.exec(stdout)) !== null) {
            networks.push({ ssid: match[1] });
        }

        res.json(networks);
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

// 🔹 Endpoint om de verbindingsstatus te controleren
app.get('/status', (req, res) => {
    exec('iwgetid -r', (error, stdout) => {
        if (error || !stdout.trim()) {
            return res.json({ connected: false });
        }

        res.json({ connected: true, ssid: stdout.trim() });
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
