require('dotenv').config();
const express = require('express');
const session = require('express-session');
const crypto = require('crypto');
const axios = require('axios');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(session({
  secret: process.env.SESSION_SECRET || 'axomex-secret-2026',
  resave: false,
  saveUninitialized: true,
  cookie: { secure: false }
}));

app.use(express.static(path.join(__dirname, 'public')));

// ---- STEP 1: Start X OAuth ----
app.get('/auth/x', (req, res) => {
  const state = crypto.randomBytes(16).toString('hex');
  const codeVerifier = crypto.randomBytes(32).toString('hex');
  const codeChallenge = crypto
    .createHash('sha256')
    .update(codeVerifier)
    .digest('base64url');

  req.session.oauthState = state;
  req.session.codeVerifier = codeVerifier;

  const params = new URLSearchParams({
    response_type: 'code',
    client_id: process.env.X_CLIENT_ID,
    redirect_uri: process.env.CALLBACK_URL,
    scope: 'tweet.read users.read follows.read like.read',
    state: state,
    code_challenge: codeChallenge,
    code_challenge_method: 'S256'
  });

  res.redirect(`https://twitter.com/i/oauth2/authorize?${params}`);
});

// ---- STEP 2: Handle Callback ----
app.get('/callback', async (req, res) => {
  const { code, state } = req.query;

  if (state !== req.session.oauthState) {
    return res.redirect('/error.html');
  }

  try {
    // Exchange code for access token
    const tokenRes = await axios.post(
      'https://api.twitter.com/2/oauth2/token',
      new URLSearchParams({
        grant_type: 'authorization_code',
        code,
        redirect_uri: process.env.CALLBACK_URL,
        client_id: process.env.X_CLIENT_ID,
        code_verifier: req.session.codeVerifier
      }),
      {
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        auth: {
          username: process.env.X_CLIENT_ID,
          password: process.env.X_CLIENT_SECRET
        }
      }
    );

    const accessToken = tokenRes.data.access_token;
    req.session.accessToken = accessToken;

    // Get user info
    const userRes = await axios.get('https://api.twitter.com/2/users/me', {
      headers: { Authorization: `Bearer ${accessToken}` }
    });

    req.session.xUser = userRes.data.data;
    res.redirect('/verify');

  } catch (err) {
    console.error('OAuth error:', err.response?.data || err.message);
    res.redirect('/error.html');
  }
});

// ---- STEP 3: Verify Tasks ----
app.get('/verify', async (req, res) => {
  if (!req.session.accessToken || !req.session.xUser) {
    return res.redirect('/auth/x');
  }

  const userId = req.session.xUser.id;
  const accessToken = req.session.accessToken;
  const targetAccount = process.env.X_TARGET_ACCOUNT;

  try {
    // Check if following @AxomexNFT
    const targetRes = await axios.get(
      `https://api.twitter.com/2/users/by/username/${targetAccount}`,
      { headers: { Authorization: `Bearer ${accessToken}` } }
    );
    const targetId = targetRes.data.data.id;

    const followRes = await axios.get(
      `https://api.twitter.com/2/users/${userId}/following?max_results=100`,
      { headers: { Authorization: `Bearer ${accessToken}` } }
    );

    const isFollowing = followRes.data.data?.some(u => u.id === targetId) || false;

    req.session.verified = { isFollowing, username: req.session.xUser.username };
    res.redirect('/whitelist-form');

  } catch (err) {
    console.error('Verify error:', err.response?.data || err.message);
    req.session.verified = { isFollowing: false, username: req.session.xUser?.username };
    res.redirect('/whitelist-form');
  }
});

// ---- API: Get session status ----
app.get('/api/status', (req, res) => {
  if (req.session.xUser) {
    res.json({
      connected: true,
      username: req.session.xUser.username,
      isFollowing: req.session.verified?.isFollowing || false
    });
  } else {
    res.json({ connected: false });
  }
});

// ---- Serve pages ----
app.get('/whitelist-form', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.listen(PORT, () => {
  console.log(`Axomex server running on port ${PORT}`);
});