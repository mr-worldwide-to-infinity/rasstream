require('dotenv').config();
const express = require('express');
const axios = require('axios');
const cors = require('cors');
const cookieParser = require('cookie-parser');
const querystring = require('querystring');
const { exec } = require('child_process');
const fs = require('fs');

const app = express();
const PORT = process.env.PORT || 3001;

app.use(cors({ origin: process.env.FRONTEND_URL, credentials: true }));
app.use(express.json());
app.use(cookieParser());

const SPOTIFY_AUTH_URL = 'https://accounts.spotify.com/authorize';
const SPOTIFY_TOKEN_URL = 'https://accounts.spotify.com/api/token';

// 🔹 1. Route om gebruiker naar Spotify login te sturen
app.get('/login', (req, res) => {
    const scope = 'user-read-private user-read-email streaming user-modify-playback-state';
    const queryParams = querystring.stringify({
        response_type: 'code',
        client_id: process.env.SPOTIFY_CLIENT_ID,
        scope: scope,
        redirect_uri: process.env.REDIRECT_URI,
    });

    res.redirect(`${SPOTIFY_AUTH_URL}?${queryParams}`);
});

// 🔹 2. Spotify stuurt gebruiker terug met een 'code', wissel deze in voor een token
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

        // Bewaar tokens in cookies
        res.cookie('access_token', response.data.access_token, { httpOnly: true });
        res.cookie('refresh_token', response.data.refresh_token, { httpOnly: true });

        res.redirect(`${process.env.FRONTEND_URL}/loggedin.html`); // Stuur gebruiker naar frontend
    } catch (error) {
        console.error("Fout bij verkrijgen van token:", error);
        res.status(500).send("Authenticatie mislukt");
    }
});

// 🔹 3. Endpoint om een nieuw access token te krijgen met het refresh token
app.post('/refresh-token', async (req, res) => {
    const refreshToken = req.cookies.refresh_token;
    if (!refreshToken) return res.status(403).json({ error: 'Geen refresh token' });

    try {
        const response = await axios.post(SPOTIFY_TOKEN_URL, new URLSearchParams({
            grant_type: 'refresh_token',
            refresh_token: refreshToken,
            client_id: process.env.SPOTIFY_CLIENT_ID,
            client_secret: process.env.SPOTIFY_CLIENT_SECRET,
        }), {
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        });

        res.cookie('access_token', response.data.access_token, { httpOnly: true });
        res.json({ access_token: response.data.access_token });
    } catch (error) {
        console.error("Fout bij vernieuwen van token:", error);
        res.status(500).json({ error: 'Kon token niet vernieuwen' });
    }
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

    const wpaSupplicantConfig = `
network={
    ssid="${ssid}"
    psk="${password}"
}
`;

    fs.appendFile('/etc/wpa_supplicant/wpa_supplicant.conf', wpaSupplicantConfig, (err) => {
        if (err) {
            console.error('Error updating WiFi config:', err);
            return res.status(500).json({ error: 'Error updating WiFi config' });
        }

        exec('wpa_cli -i wlan0 reconfigure', (error) => {
            if (error) {
                console.error('Error reconnecting to WiFi:', error);
                return res.status(500).json({ error: 'Error reconnecting to WiFi' });
            }

            res.json({ success: true });
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

// 🔹 4. Start de server
app.listen(PORT, () => {
    console.log(`Server draait op http://localhost:${PORT}`);
});
