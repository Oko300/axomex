const axios = require('axios');

function parseCookies(req) {
  const list = {};
  const cookieHeader = req.headers.cookie;
  if (!cookieHeader) return list;
  cookieHeader.split(';').forEach(cookie => {
    let [name, ...rest] = cookie.split('=');
    name = name?.trim();
    if (!name) return;
    try { list[name] = decodeURIComponent(rest.join('=').trim()); }
    catch(e) { list[name] = rest.join('=').trim(); }
  });
  return list;
}

module.exports = async (req, res) => {
  const { code, state } = req.query;
  const cookies = parseCookies(req);

  if (!code) return res.redirect('/?error=no_code');
  if (!state || state !== cookies.oauth_state) return res.redirect('/?error=state_mismatch');

  const codeVerifier = cookies.code_verifier;
  if (!codeVerifier) return res.redirect('/?error=no_verifier');

  try {
    // Exchange code for token
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

    // Get user info
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

    // Store in cookie — secure settings
    const userData = JSON.stringify({
      username: user.username,
      name: user.name,
      isFollowing
    });

    const cookieValue = encodeURIComponent(userData);

    res.setHeader('Set-Cookie', [
      `x_user=${cookieValue}; Path=/; HttpOnly=false; SameSite=Lax; Max-Age=7200`,
      `oauth_state=; Path=/; Max-Age=0`,
      `code_verifier=; Path=/; Max-Age=0`
    ]);

    res.redirect('/#whitelist');

  } catch(err) {
    console.error('Callback error:', err.response?.data || err.message);
    res.redirect('/?error=auth_failed');
  }
};