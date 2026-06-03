# patch-html.ps1
# Run from your axomex project root:
#   powershell -ExecutionPolicy Bypass -File patch-html.ps1

$file = "public\index.html"
$html = Get-Content $file -Raw -Encoding utf8

# ── PATCH 1: Replace the follow step body ──────────────────────────────────
$oldFollow = @'
              <a href="https://x.com/intent/follow?screen_name=AxomexNFT" target="_blank" class="step-btn x-btn">
                <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-4.714-6.231-5.401 6.231H2.746l7.73-8.835L1.254 2.25H8.08l4.253 5.622 5.911-5.622z"/></svg>
                Follow on X
              </a>
              <button onclick="confirmFollow()" class="step-btn" style="background:rgba(62,207,178,0.15);border:1px solid rgba(62,207,178,0.4);color:var(--teal);margin-top:0.5rem;cursor:pointer;">
                ✅ I have followed Verify
              </button>
'@

$newFollow = @'
              <a href="https://x.com/intent/follow?screen_name=AxomexNFT" target="_blank" class="step-btn x-btn" id="follow-btn">
                <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-4.714-6.231-5.401 6.231H2.746l7.73-8.835L1.254 2.25H8.08l4.253 5.622 5.911-5.622z"/></svg>
                Follow on X
              </a>
              <p id="follow-status" style="display:none;margin-top:0.5rem;font-size:0.82rem;font-weight:700;"></p>
              <label class="manual-confirm" id="manual-follow-wrap" style="display:none;margin-top:0.5rem;">
                <input type="checkbox" id="manual-follow-check" />
                <span>I have followed — tap to verify now</span>
              </label>
'@

$html = $html.Replace($oldFollow, $newFollow)

# ── PATCH 2: Replace the tweet step link+checkbox with auto-verify version ──
$oldTweet = @'
              <a id="tweet-btn"
                href="https://x.com/intent/tweet?text=I%20just%20applied%20for%20%40AxomexNFT%20whitelist!%201%2C111%20unique%20axolotls%20are%20coming.%20Free%20Mint!%20Join%20now%3A%20axomex.xyz"
                target="_blank" class="step-btn tweet-btn" >
                <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-4.714-6.231-5.401 6.231H2.746l7.73-8.835L1.254 2.25H8.08l4.253 5.622 5.911-5.622z"/></svg>
                Post Tweet Now
              </a>
              <label class="manual-confirm" style="margin-top:0.5rem;">
                <input type="checkbox" onchange="manualMark(this, 'tweet')" />
                <span>I have posted the tweet and copied the link ✓</span>
              </label>
              <span style="display:none">
              </a>
'@

$newTweet = @'
              <a id="tweet-btn"
                href="https://x.com/intent/tweet?text=I%20just%20applied%20for%20%40AxomexNFT%20whitelist!%201%2C111%20unique%20axolotls%20are%20coming.%20Free%20Mint!%20Join%20now%3A%20axomex.xyz"
                target="_blank" class="step-btn tweet-btn">
                <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-4.714-6.231-5.401 6.231H2.746l7.73-8.835L1.254 2.25H8.08l4.253 5.622 5.911-5.622z"/></svg>
                Post Tweet Now
              </a>
              <p id="tweet-status" style="display:none;margin-top:0.5rem;font-size:0.82rem;font-weight:700;"></p>
              <label class="manual-confirm" id="tweet-manual-wrap" style="display:none;margin-top:0.5rem;">
                <input type="checkbox" id="tweet-manual-check" />
                <span>I have posted the tweet and copied the link ✓</span>
              </label>
'@

$html = $html.Replace($oldTweet, $newTweet)

# ── PATCH 3: Replace the entire <script> block with the new auto-verify one ─
$oldScript = @'
  <script>
    const ADMIN_KEY = 'axomex2026';
    let userConnected = false;
    let userFollowing = false;
    let tweetPosted = false;
'@

# Find the closing </script> after the opening <script> tag
# We'll replace everything from <script> to the final </script>
$scriptStart = $html.IndexOf("  <script>`r`n    const ADMIN_KEY")
if ($scriptStart -lt 0) {
    $scriptStart = $html.IndexOf("  <script>" + [char]10 + "    const ADMIN_KEY")
}

# Find </script> after that position
$scriptEnd = $html.IndexOf("</script>", $scriptStart) + "</script>".Length

$oldScriptBlock = $html.Substring($scriptStart, $scriptEnd - $scriptStart)

$newScriptBlock = @'
  <script>
  /* ================================================================
     AXOMEX — Auto-verification engine
     Polls /api/status for follow check (Step 2)
     Polls /api/verify-tweet for tweet check (Step 5)
     Unlocks submit button when both are confirmed
  ================================================================ */
  (function () {
    'use strict';

    const POLL_MS      = 5000;
    const MAX_POLLS    = 36; // 3 minutes

    let state = { connected: false, username: null, isFollowing: false, tweetVerified: false };
    let followTimer = null, tweetTimer = null;
    let followTries = 0, tweetTries = 0;

    // ── helpers ──
    function $(id) { return document.getElementById(id); }

    function markDone(stepId, checkId) {
      const s = $(stepId); if (s) s.classList.add('done');
      const c = $(checkId); if (c) c.classList.add('visible');
    }

    function setMsg(id, msg, color) {
      const el = $(id); if (!el) return;
      el.textContent = msg;
      el.style.color = color || 'var(--teal)';
      el.style.display = msg ? 'block' : 'none';
    }

    function updateSubmit() {
      const btn  = $('submit-btn');
      const lock = $('lock-notice');
      if (!btn) return;
      const ok = state.connected && state.isFollowing && state.tweetVerified;
      if (ok) {
        btn.classList.remove('btn-locked');
        btn.removeAttribute('onclick');
        if (lock) lock.style.display = 'none';
      } else {
        btn.classList.add('btn-locked');
        if (lock) {
          lock.style.display = 'block';
          if (!state.connected)     lock.textContent = '🔒 Connect your X account to unlock submission';
          else if (!state.isFollowing)  lock.textContent = '🔒 Follow @AxomexNFT to unlock submission';
          else                      lock.textContent = '🔒 Post the required tweet to unlock submission';
        }
      }
    }

    // ── API calls ──
    async function fetchStatus() {
      try {
        const r = await fetch('/api/status', { credentials: 'include' });
        return r.ok ? r.json() : null;
      } catch { return null; }
    }

    async function fetchTweetVerify() {
      try {
        const r = await fetch('/api/verify-tweet', { credentials: 'include' });
        return r.ok ? r.json() : null;
      } catch { return null; }
    }

    // ── apply state to DOM ──
    function applyState() {
      if (state.connected) {
        markDone('step-connect', 'check-connect');
        // Show username in connect step
        const cs = $('connect-status');
        if (cs) cs.textContent = 'Connected as @' + state.username;
        const cw = $('connect-btn-wrap');
        if (cw) cw.innerHTML = '<a href="/auth/x" class="step-btn x-btn" style="font-size:0.78rem;opacity:0.7;">Switch Account</a>';
      }
      if (state.isFollowing) {
        markDone('step-follow', 'check-follow');
        stopFollowPoll();
        setMsg('follow-status', '✓ Verified — you are following @AxomexNFT');
      }
      if (state.tweetVerified) {
        markDone('step-tweet', 'check-tweet');
        stopTweetPoll();
        setMsg('tweet-status', '✓ Tweet verified!');
        const tc = $('tweet-manual-check');
        if (tc) { tc.checked = true; tc.disabled = true; }
      }
      updateSubmit();
    }

    // ── follow polling ──
    function startFollowPoll() {
      if (followTimer) return;
      followTries = 0;
      setMsg('follow-status', '⏳ Checking follow status…', 'var(--muted)');
      followTimer = setInterval(async () => {
        followTries++;
        const d = await fetchStatus();
        if (d?.isFollowing) { state.isFollowing = true; applyState(); return; }
        if (followTries >= MAX_POLLS) {
          stopFollowPoll();
          setMsg('follow-status', '⚠ Auto-check timed out.', '#e74c3c');
          const w = $('manual-follow-wrap'); if (w) w.style.display = 'flex';
        }
      }, POLL_MS);
    }
    function stopFollowPoll() { if (followTimer) { clearInterval(followTimer); followTimer = null; } }

    // ── tweet polling ──
    function startTweetPoll() {
      if (tweetTimer) return;
      tweetTries = 0;
      setMsg('tweet-status', '⏳ Waiting for your tweet…', 'var(--muted)');
      tweetTimer = setInterval(async () => {
        tweetTries++;
        const d = await fetchTweetVerify();
        if (d?.verified) { state.tweetVerified = true; applyState(); return; }
        if (tweetTries >= MAX_POLLS) {
          stopTweetPoll();
          setMsg('tweet-status', '⚠ Could not auto-detect tweet.', '#e74c3c');
          const w = $('tweet-manual-wrap'); if (w) w.style.display = 'flex';
        }
      }, POLL_MS);
    }
    function stopTweetPoll() { if (tweetTimer) { clearInterval(tweetTimer); tweetTimer = null; } }

    // ── wire events ──
    function wireEvents() {
      // Follow link — start polling after click
      const fb = $('follow-btn');
      if (fb) fb.addEventListener('click', () => { if (state.connected) setTimeout(startFollowPoll, 2000); });

      // Manual follow fallback
      const mf = $('manual-follow-check');
      if (mf) mf.addEventListener('change', () => {
        if (!mf.checked) return;
        fetchStatus().then(d => {
          if (d?.isFollowing) { state.isFollowing = true; applyState(); }
          else startFollowPoll();
        });
      });

      // Tweet button — start polling after click
      const tb = $('tweet-btn');
      if (tb) tb.addEventListener('click', () => { setTimeout(startTweetPoll, 4000); });

      // Manual tweet fallback
      const mt = $('tweet-manual-check');
      if (mt) mt.addEventListener('change', () => {
        if (!mt.checked) return;
        fetchTweetVerify().then(d => {
          state.tweetVerified = true; // accept manual as fallback
          applyState();
        });
      });

      // Block locked submit
      const sb = $('submit-btn');
      if (sb) sb.addEventListener('click', e => {
        if (sb.classList.contains('btn-locked')) e.preventDefault();
      });
    }

    // ── init ──
    async function init() {
      const d = await fetchStatus();
      if (d && !d.error) {
        state.connected     = true;
        state.username      = d.username || '';
        state.isFollowing   = d.isFollowing  || false;
        state.tweetVerified = d.tweetVerified || false;
      }
      applyState();
      wireEvents();
    }

    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
    else init();

    // Keep admin functions alive (used by hidden buttons in HTML)
    window.closeWhitelist = function() {
      if (prompt('Admin key?') !== 'axomex2026') return alert('Wrong key.');
      $('wl-open').style.display = 'none';
      $('wl-closed').style.display = 'block';
      alert('Whitelist is now CLOSED.');
    };
    window.openWhitelist = function() {
      if (prompt('Admin key?') !== 'axomex2026') return alert('Wrong key.');
      $('wl-open').style.display = 'block';
      $('wl-closed').style.display = 'none';
      alert('Whitelist is now OPEN.');
    };
    window.incrementSpots = function() {}; // no-op, kept for onclick compat
  })();
  </script>
'@

$html = $html.Replace($oldScriptBlock, $newScriptBlock)

# ── Save ──
$html | Set-Content $file -Encoding utf8 -NoNewline
Write-Host "✅ patch-html.ps1 done — public\index.html updated."
