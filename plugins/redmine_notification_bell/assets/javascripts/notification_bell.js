(function () {
  'use strict';

  // ── Config (overridden by window.NotificationBellConfig) ────
  var cfg = window.NotificationBellConfig || {};
  var POLL_INTERVAL_MS     = 30000;
  var SOUND_ENABLED        = cfg.soundEnabled !== false;   // default true
  var MAX_NOTIFICATIONS    = cfg.maxNotifications || 20;
  var prevUnreadCount      = -1;  // -1 = first load

  // ── DOM refs (set after DOMContentLoaded) ───────────────────
  var wrapper, bellBtn, bellIcon, badge, panel, list, markAllBtn;

  // ── Web Audio notification sound ────────────────────────────
  function playNotificationSound() {
    try {
      var ctx = new (window.AudioContext || window.webkitAudioContext)();

      function beep(freq, start, duration, vol) {
        var osc   = ctx.createOscillator();
        var gain  = ctx.createGain();
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.type = 'sine';
        osc.frequency.value = freq;
        gain.gain.setValueAtTime(vol, ctx.currentTime + start);
        gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + start + duration);
        osc.start(ctx.currentTime + start);
        osc.stop(ctx.currentTime + start + duration);
      }

      beep(880, 0,    0.12, 0.4);
      beep(1100, 0.13, 0.12, 0.35);
      beep(1320, 0.26, 0.18, 0.3);
    } catch (e) {
      // Audio not available — silently ignore
    }
  }

  // ── Badge helpers ────────────────────────────────────────────
  function updateBadge(count) {
    if (!badge) return;
    if (count > 0) {
      badge.textContent = count > 99 ? '99+' : String(count);
      badge.style.display = 'flex';
    } else {
      badge.style.display = 'none';
    }
  }

  function ringBell() {
    if (!bellIcon) return;
    bellIcon.classList.remove('nb-ringing');
    // Force reflow so the animation restarts
    void bellIcon.offsetWidth;
    bellIcon.classList.add('nb-ringing');
    bellIcon.addEventListener('animationend', function () {
      bellIcon.classList.remove('nb-ringing');
    }, { once: true });
  }

  // ── Panel open/close ─────────────────────────────────────────
  function openPanel() {
    panel.style.display = 'flex';
    fetchNotifications();
  }

  function closePanel() {
    panel.style.display = 'none';
  }

  function isPanelOpen() {
    return panel && panel.style.display !== 'none';
  }

  // ── CSRF token ───────────────────────────────────────────────
  function csrfToken() {
    var m = document.querySelector('meta[name="csrf-token"]');
    return m ? m.getAttribute('content') : '';
  }

  // ── Fetch notification list ───────────────────────────────────
  function fetchNotifications() {
    if (!list) return;
    list.innerHTML = '<div class="nb-empty">Loading…</div>';

    var xhr = new XMLHttpRequest();
    xhr.open('GET', '/notification_bells?limit=' + MAX_NOTIFICATIONS, true);
    xhr.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
    xhr.setRequestHeader('Accept', 'application/json');
    xhr.onload = function () {
      if (xhr.status === 200) {
        try {
          var data = JSON.parse(xhr.responseText);
          renderList(data.notifications || []);
          updateBadge(data.unread_count || 0);
          prevUnreadCount = data.unread_count || 0;
        } catch (e) {
          list.innerHTML = '<div class="nb-empty">Error loading notifications.</div>';
        }
      } else if (xhr.status === 401 || xhr.status === 403 || xhr.status === 302) {
        if (wrapper) wrapper.style.display = 'none';
      }
    };
    xhr.send();
  }

  // ── Render the notification items ────────────────────────────
  function renderList(notifications) {
    if (!list) return;
    if (!notifications.length) {
      list.innerHTML = '<div class="nb-empty">No notifications yet.</div>';
      return;
    }

    list.innerHTML = '';
    notifications.forEach(function (n) {
      var item = document.createElement('a');
      item.href = n.url;
      item.className = 'nb-item' + (n.read ? '' : ' nb-unread');
      item.setAttribute('data-id', n.id);
      item.setAttribute('data-read', n.read ? '1' : '0');

      item.innerHTML =
        '<span class="nb-item-subject">#' + n.issue_id + ' &ndash; ' + escapeHtml(n.issue_subject) + '</span>' +
        '<span class="nb-item-meta">' +
          '<span class="nb-item-author">Mentioned by ' + escapeHtml(n.author_name) + '</span>' +
          '<span class="nb-item-time">' + escapeHtml(n.created_at) + '</span>' +
        '</span>';

      item.addEventListener('click', function (e) {
        if (item.getAttribute('data-read') === '0') {
          markRead(n.id, item);
        }
        closePanel();
      });

      list.appendChild(item);
    });
  }

  // ── Mark single notification as read ─────────────────────────
  function markRead(id, itemEl) {
    var xhr = new XMLHttpRequest();
    xhr.open('POST', '/notification_bells/' + id + '/read', true);
    xhr.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
    xhr.setRequestHeader('X-CSRF-Token', csrfToken());
    xhr.setRequestHeader('Accept', 'application/json');
    xhr.setRequestHeader('Content-Type', 'application/json');
    xhr.onload = function () {
      if (xhr.status === 200) {
        try {
          var data = JSON.parse(xhr.responseText);
          if (itemEl) {
            itemEl.classList.remove('nb-unread');
            itemEl.setAttribute('data-read', '1');
          }
          updateBadge(data.unread_count || 0);
          prevUnreadCount = data.unread_count || 0;
        } catch (e) { /* ignore */ }
      }
    };
    xhr.send();
  }

  // ── Mark all as read ─────────────────────────────────────────
  function markAllRead() {
    var xhr = new XMLHttpRequest();
    xhr.open('POST', '/notification_bells/read_all', true);
    xhr.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
    xhr.setRequestHeader('X-CSRF-Token', csrfToken());
    xhr.setRequestHeader('Accept', 'application/json');
    xhr.setRequestHeader('Content-Type', 'application/json');
    xhr.onload = function () {
      if (xhr.status === 200) {
        updateBadge(0);
        prevUnreadCount = 0;
        // Update all items in the list to read
        var items = list.querySelectorAll('.nb-item.nb-unread');
        items.forEach(function (el) {
          el.classList.remove('nb-unread');
          el.setAttribute('data-read', '1');
        });
      }
    };
    xhr.send();
  }

  // ── Poll for new notification count ──────────────────────────
  function pollCount() {
    var xhr = new XMLHttpRequest();
    xhr.open('GET', '/notification_bells/count?_=' + new Date().getTime(), true);
    xhr.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
    xhr.setRequestHeader('Accept', 'application/json');
    xhr.setRequestHeader('Cache-Control', 'no-cache');
    xhr.onload = function () {
      if (xhr.status === 401 || xhr.status === 403) {
        // Session expired — hide the widget rather than flooding the console
        if (wrapper) wrapper.style.display = 'none';
        return;
      }
      if (xhr.status === 200) {
        try {
          var data  = JSON.parse(xhr.responseText);
          var count = data.unread_count || 0;

          // New notifications arrived since last poll
          if (prevUnreadCount !== -1 && count > prevUnreadCount) {
            if (SOUND_ENABLED) playNotificationSound();
            ringBell();
            // Refresh open panel immediately
            if (isPanelOpen()) fetchNotifications();
          }

          updateBadge(count);
          prevUnreadCount = count;
        } catch (e) { /* ignore parse errors */ }
      }
    };
    xhr.onerror = function () { /* network error — skip */ };
    xhr.send();
  }

  // ── HTML escaping ─────────────────────────────────────────────
  function escapeHtml(str) {
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  // ── Position the bell widget next to the search box ──────────
  function positionBellWidget() {
    if (!wrapper) return;

    // Try common Redmine search form selectors
    var searchForm =
      document.querySelector('#search-form') ||
      document.querySelector('form[action*="search"]') ||
      document.querySelector('#header form') ||
      document.querySelector('.quick-search');

    if (searchForm && searchForm.parentNode) {
      searchForm.parentNode.insertBefore(wrapper, searchForm);
      wrapper.style.display = 'inline-flex';
    } else {
      // Fallback: keep it in the top-right corner as fixed overlay
      wrapper.style.position = 'fixed';
      wrapper.style.top      = '8px';
      wrapper.style.right    = '12px';
      wrapper.style.zIndex   = '10000';
      document.body.appendChild(wrapper);
    }
  }

  // ── Bootstrap ─────────────────────────────────────────────────
  function init() {
    wrapper    = document.getElementById('nb-bell-wrapper');
    bellBtn    = document.getElementById('nb-bell-btn');
    bellIcon   = bellBtn && bellBtn.querySelector('.nb-bell-icon');
    badge      = document.getElementById('nb-badge');
    panel      = document.getElementById('nb-panel');
    list       = document.getElementById('nb-list');
    markAllBtn = document.getElementById('nb-mark-all');

    if (!wrapper) return; // User not logged in — nothing to do

    positionBellWidget();

    // Bell button toggle
    bellBtn.addEventListener('click', function (e) {
      e.stopPropagation();
      isPanelOpen() ? closePanel() : openPanel();
    });

    // Mark-all button
    if (markAllBtn) {
      markAllBtn.addEventListener('click', function (e) {
        e.stopPropagation();
        markAllRead();
      });
    }

    // Close panel when clicking outside
    document.addEventListener('click', function (e) {
      if (wrapper && !wrapper.contains(e.target)) {
        closePanel();
      }
    });

    // Initial count fetch
    pollCount();

    // Periodic polling
    setInterval(pollCount, POLL_INTERVAL_MS);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
