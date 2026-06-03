const axios = require('axios');

function parseCookies(req) {
  const list = {};
  const h = req.headers.cookie;
  if (!h) return list;
  h.split(';').forEach(c => {
    let [n, ...v] = c.split('=');
    n = n?.trim();
    if (n) try { list[n] = decodeURIComponent(v.join('=').trim()); } catch(e) { list[n] = v.join('=').trim(); }
  });
  return list;
}

module.exports = async (req, res) => {
  const { code, state: returnedState } = req.query;
  if (!code || !returnedState) return res.redirect('/?error=missing_params');

  // Decode the combined state|verifier we encoded in auth.js
  let stateObj;
  try {
    stateObj = JSON.parse(Buffer.from(returnedState, 'base64url').toString());
  } catch(e) {
    return res.redirect('/?error=bad_state');
  }

  const { codeVerifier } = stateObj;
  if (!codeVerifier) return res.redirect('/?error=no_verifier');

  try {
    // Exchange code for token using Basic Auth (confidential client)
    const tokenRes = await axios.post(
      'https://api.twitter.com/2/oauth2/token',
      new URLSearchParams({
        grant_type: 'authorization_code',
        code,
        redirect_uri: process.env.CALLBACK_URL,
        client_id: process.env.X_CLIENT_ID,
        code_verifier: codeVerifier
      }).toString(),
      {
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        auth: {
          username: process.env.X_CLIENT_ID,
          password: process.env.X_CLIENT_SECRET
        }
      }
    );

    const accessToken = tokenRes.data.access_token;

    // Get user profile
    const userRes = await axios.get('https://api.twitter.com/2/users/me', {
      headers: { Authorization: `Bearer ${accessToken}` }
    });
    const user = userRes.data.data;

    // Check if following @AxomexNFT
    let isFollowing = false;
    try {
      const targetRes = await axios.get(
        `https://api.twitter.com/2/users/by/username/${process.env.X_TARGET_ACCOUNT}`,
        { headers: { Authorization: `Bearer ${accessToken}` } }
      );
      const targetId = targetRes.data.data.id;
      const followRes = await axios.get(
        `https://api.twitter.com/2/users/${user.id}/following?max_results=1000`,
        { headers: { Authorization: `Bearer ${accessToken}` } }
      );
      isFollowing = followRes.data.data?.some(u => u.id === targetId) || false;
    } catch(e) {
      console.error('Follow check error:', e.response?.data || e.message);
    }

    // Set user data cookie
    const userData = encodeURIComponent(JSON.stringify({ username: user.username, isFollowing }));
    res.setHeader('Set-Cookie', [
      `x_user=${userData}; Path=/; SameSite=Lax; Max-Age=7200; Secure`,
      `cv=; Path=/; Max-Age=0`
    ]);

    // Also pass in URL hash as primary method (localStorage backup)
    res.redirect(`/#connected=${encodeURIComponent(user.username)}&following=${isFollowing}`);

  } catch(err) {
    console.error('Callback error:', JSON.stringify(err.response?.data || err.message));
    res.redirect('/?error=token_exchange_failed');
  }
};