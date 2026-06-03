# patch-html.ps1  —  Run from axomex project root
# powershell -ExecutionPolicy Bypass -File patch-html.ps1

$file = "public\index.html"
$html = Get-Content $file -Raw -Encoding utf8

# ── PATCH 1: Follow step — replace old button with "I have followed" verify button ──
$oldFollow = '<button onclick="confirmFollow()" class="step-btn" style="background:rgba(62,207,178,0.15);border:1px solid rgba(62,207,178,0.4);color:var(--teal);margin-top:0.5rem;cursor:pointer;">
                ✅ I have followed Verify
              </button>'

$newFollow = '<button id="confirm-follow-btn" class="step-btn" style="background:rgba(62,207,178,0.15);border:1px solid rgba(62,207,178,0.4);color:var(--teal);margin-top:0.5rem;cursor:pointer;">
                ✅ I have followed — Verify
              </button>
              <p id="follow-status" style="display:none;margin-top:0.5rem;font-size:0.82rem;font-weight:700;"></p>'

$html = $html.Replace($oldFollow, $newFollow)

# ── PATCH 2: Tweet checkbox — replace old onchange with id ──
$oldTweetCheck = '<input type="checkbox" onchange="manualMark(this, ''tweet'')" />'
$newTweetCheck = '<input type="checkbox" id="tweet-done-check" />'
$html = $html.Replace($oldTweetCheck, $newTweetCheck)

# Also add status message after the tweet label closing tag
$oldTweetLabel = '<span>I have posted the tweet and copied the link ✓</span>
              </label>
              <span style="display:none">
              </a>'
$newTweetLabel = '<span>I have posted the tweet and copied the link ✓</span>
              </label>
              <p id="tweet-status" style="display:none;margin-top:0.5rem;font-size:0.82rem;font-weight:700;"></p>'
$html = $html.Replace($oldTweetLabel, $newTweetLabel)

# ── PATCH 3: Replace entire <script> block ──────────────────────────────────
# Find start and end of script block
$scriptStart = $html.IndexOf('<script>')
# Find the LAST </script> (the main one)
$scriptEnd = $html.LastIndexOf('</script>') + '</script>'.Length
$oldScript = $html.Substring($scriptStart, $scriptEnd - $scriptStart)

$newScript = @'
<script>
(function () {
  'use strict';

  function $(id) { return document.getElementById(id); }

  function markDone(stepId, checkId) {
    var s = $(stepId); if (s) s.classList.add('done');
    var c = $(checkId); if (c) c.classList.add('visible');
  }

  function setMsg(id, msg, color) {
    var el = $(id); if (!el) return;
    el.textContent = msg;
    el.style.color = color || 'var(--teal)';
    el.style.display = msg ? 'block' : 'none';
  }

  var state = { connected: false, isFollowing: false, tweetVerified: false };

  function updateSubmit() {
    var btn  = $('submit-btn');
    var lock = $('lock-notice');
    if (!btn) return;
    var ok = state.connected && state.isFollowing && state.tweetVerified;
    if (ok) {
      btn.classList.remove('btn-locked');
      if (lock) lock.style.display = 'none';
    } else {
      btn.classList.add('btn-locked');
      if (lock) {
        lock.style.display = 'block';
        if (!state.connected)       lock.textContent = 'Connect your X account to unlock submission';
        else if (!state.isFollowing) lock.textContent = 'Follow @AxomexNFT to unlock submission';
        else                         lock.textContent = 'Post the required tweet to unlock submission';
      }
    }
  }

  // ── On page load: check current status from server ──
  async function init() {
    try {
      var r = await fetch('/api/status', { credentials: 'include' });
      if (r.ok) {
        var d = await r.json();
        if (d && !d.error) {
          state.connected     = true;
          state.isFollowing   = d.isFollowing   || false;
          state.tweetVerified = d.tweetVerified || false;

          // Restore UI for already-connected user
          var cs = $('connect-status');
          if (cs) cs.textContent = 'Connected as @' + (d.username || '');
          var cw = $('connect-btn-wrap');
          if (cw) cw.innerHTML = '<a href="/auth/x" class="step-btn x-btn" style="font-size:0.78rem;opacity:0.7;">Switch Account</a>';
          markDone('step-connect', 'check-connect');

          if (state.isFollowing) {
            markDone('step-follow', 'check-follow');
            setMsg('follow-status', '✓ Already following @AxomexNFT');
          }
          if (state.tweetVerified) {
            markDone('step-tweet', 'check-tweet');
            setMsg('tweet-status', '✓ Tweet already verified!');
            var tc = $('tweet-done-check'); if (tc) { tc.checked = true; tc.disabled = true; }
          }
        }
      }
    } catch(e) {}
    updateSubmit();
    wireEvents();
  }

  function wireEvents() {

    // ── Step 2: "I have followed" button ──
    var fb = $('confirm-follow-btn');
    if (fb) {
      fb.addEventListener('click', async function () {
        fb.textContent = 'Checking…';
        fb.disabled = true;
        try {
          var r = await fetch('/api/status', { credentials: 'include' });
          var d = r.ok ? await r.json() : null;
          if (d && d.isFollowing) {
            state.isFollowing = true;
            markDone('step-follow', 'check-follow');
            setMsg('follow-status', '✓ Verified — you are following @AxomexNFT');
            fb.style.display = 'none';
          } else {
            setMsg('follow-status', '⚠ Not detected yet. Follow @AxomexNFT then try again.', '#e74c3c');
            fb.textContent = '✅ I have followed — Verify';
            fb.disabled = false;
          }
        } catch(e) {
          setMsg('follow-status', '⚠ Error checking. Please try again.', '#e74c3c');
          fb.textContent = '✅ I have followed — Verify';
          fb.disabled = false;
        }
        updateSubmit();
      });
    }

    // ── Step 5: tweet checkbox ──
    var tc = $('tweet-done-check');
    if (tc) {
      tc.addEventListener('change', async function () {
        if (!tc.checked) return;
        setMsg('tweet-status', '⏳ Verifying your tweet…', 'var(--muted)');
        try {
          var r = await fetch('/api/verify-tweet', { credentials: 'include' });
          var d = r.ok ? await r.json() : null;
          if (d && d.verified) {
            state.tweetVerified = true;
            markDone('step-tweet', 'check-tweet');
            setMsg('tweet-status', '✓ Tweet verified! Submission unlocked.');
            tc.disabled = true;
          } else {
            setMsg('tweet-status', '⚠ Tweet not found yet. Post it then tick again.', '#e74c3c');
            tc.checked = false;
          }
        } catch(e) {
          setMsg('tweet-status', '⚠ Error verifying. Please try again.', '#e74c3c');
          tc.checked = false;
        }
        updateSubmit();
      });
    }

    // Block locked submit button
    var sb = $('submit-btn');
    if (sb) {
      sb.addEventListener('click', function(e) {
        if (sb.classList.contains('btn-locked')) e.preventDefault();
      });
    }
  }

  // ── Admin helpers (keep working) ──
  window.closeWhitelist = function() {
    if (prompt('Admin key?') !== 'axomex2026') return alert('Wrong key.');
    var o = $('wl-open'); if (o) o.style.display = 'none';
    var c = $('wl-closed'); if (c) c.style.display = 'block';
    alert('Whitelist is now CLOSED.');
  };
  window.openWhitelist = function() {
    if (prompt('Admin key?') !== 'axomex2026') return alert('Wrong key.');
    var o = $('wl-open'); if (o) o.style.display = 'block';
    var c = $('wl-closed'); if (c) c.style.display = 'none';
    alert('Whitelist is now OPEN.');
  };
  window.incrementSpots = function() {};

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
</script>
'@

$html = $html.Replace($oldScript, $newScript)

$html | Set-Content $file -Encoding utf8 -NoNewline
Write-Host "Done — public\index.html patched."