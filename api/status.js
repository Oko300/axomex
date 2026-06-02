function parseCookies(req) {
  const list = {};
  const cookieHeader = req.headers.cookie;
  if (!cookieHeader) return list;
  cookieHeader.split(';').forEach(cookie => {
    let [name, ...rest] = cookie.split('=');
    name = name?.trim();
    if (!name) return;
    const value = rest.join('=').trim();
    try {
      list[name] = decodeURIComponent(value);
    } catch(e) {
      list[name] = value;
    }
  });
  return list;
}

module.exports = (req, res) => {
  res.setHeader('Content-Type', 'application/json');
  res.setHeader('Cache-Control', 'no-store');

  const cookies = parseCookies(req);

  console.log('Cookies received:', Object.keys(cookies));

  if (cookies.x_user) {
    try {
      const user = JSON.parse(cookies.x_user);
      return res.json({
        connected: true,
        username: user.username,
        isFollowing: user.isFollowing || false
      });
    } catch(e) {
      console.error('Cookie parse error:', e.message);
      return res.json({ connected: false, error: 'parse_error' });
    }
  }

  return res.json({ connected: false });
};