const crypto = require('crypto');

module.exports = (req, res) => {
  const state = crypto.randomBytes(16).toString('hex');
  const codeVerifier = crypto.randomBytes(32).toString('hex');
  const codeChallenge = crypto
    .createHash('sha256')
    .update(codeVerifier)
    .digest('base64url');

  // Store in cookie
  res.setHeader('Set-Cookie', [
    `oauth_state=${state}; Path=/; HttpOnly; SameSite=Lax`,
    `code_verifier=${codeVerifier}; Path=/; HttpOnly; SameSite=Lax`
  ]);

  const params = new URLSearchParams({
    response_type: 'code',
    client_id: process.env.X_CLIENT_ID,
    redirect_uri: process.env.CALLBACK_URL,
    scope: 'tweet.read users.read follows.read like.read',
    state,
    code_challenge: codeChallenge,
    code_challenge_method: 'S256'
  });

  res.redirect(`https://twitter.com/i/oauth2/authorize?${params}`);
};