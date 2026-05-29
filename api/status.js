function parseCookies(req) {
  const list = {};
  const cookieHeader = req.headers.cookie;
  if (!cookieHeader) return list;
  cookieHeader.split(';').forEach(cookie => {
    let [name, ...rest] = cookie.split('=');
    name = name?.trim();
    if (!name) return;
    const value = rest.join('=').trim();
    list[name] = decodeURIComponent(value);
  });
  return list;
}

module.exports = (req, res) => {
  const cookies = parseCookies(req);
  res.setHeader('Content-Type', 'application/json');

  if (cookies.x_user) {
    try {
      const user = JSON.parse(cookies.x_user);
      res.json({ connected: true, username: user.username, isFollowing: user.isFollowing });
    } catch {
      res.json({ connected: false });
    }
  } else {
    res.json({ connected: false });
  }
};