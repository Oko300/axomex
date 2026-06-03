const crypto = require('crypto');

module.exports = (req, res) => {
  // Generate state and code verifier
  const state = crypto.randomBytes(16).toString('hex');
  const codeVerifier = crypto.randomBytes(32).toString('base64url');
  const codeChallenge = crypto
    .createHash('sha256')
    .update(codeVerifier)
    .digest('base64url');

  // Encode verifier into state so it survives the redirect
  // Format: state|codeVerifier (base64 encoded)
  const combined = Buffer.from(JSON.stringify({ state, codeVerifier })).toString('base64url');

  const params = new URLSearchParams({
    response_type: 'code',
    client_id: process.env.X_CLIENT_ID,
    redirect_uri: process.env.CALLBACK_URL,
    scope: 'tweet.read users.read follows.read like.read',
    state: combined,
    code_challenge: codeChallenge,
    code_challenge_method: 'S256'
  });

  // Also set cookie as backup
  res.setHeader('Set-Cookie', `cv=${combined}; Path=/; HttpOnly; SameSite=Lax; Max-Age=600; Secure`);
  res.redirect(`https://twitter.com/i/oauth2/authorize?${params}`);
};