(function () {
  'use strict';

  // ── Config (overridden by window.NotificationBellConfig) ────
  var cfg              = window.NotificationBellConfig || {};
  var POLL_INTERVAL_MS = 5000;
  var SOUND_ENABLED    = cfg.soundEnabled !== false;
  var MAX_NOTIFICATIONS = cfg.maxNotifications || 20;

  var prevUnreadCount  = -1;
  var readVisible      = false;

  // ── Scroll to note anchor on page load ───────────────────────
  // When arriving from a notification click (_nb param present) the page's
  // own JavaScript can reset scroll before the browser reaches the anchor.
  // Re-apply the scroll after the page has fully settled.
  (function scrollToNoteAnchor() {
    var params = new URLSearchParams(window.location.search);
    if (!params.has('_nb')) return;          // not a notification navigation
    var hash = window.location.hash;         // e.g. "#note-3"
    if (!hash) return;

    function tryScroll(attemptsLeft) {
      var target = document.querySelector(hash) ||
                   document.querySelector('[id$="' + hash.replace('#', '') + '"]');
      if (target) {
        target.scrollIntoView({ behavior: 'smooth', block: 'start' });
        target.style.transition = 'background 0.5s';
        target.style.background = '#fff9c4';
        setTimeout(function () { target.style.background = ''; }, 3000);
        // Remove _nb from the URL so a manual page reload doesn't re-trigger
        // the scroll and highlight — it was only needed for the initial click.
        history.replaceState(null, '', window.location.pathname + hash);
      } else if (attemptsLeft > 0) {
        setTimeout(function () { tryScroll(attemptsLeft - 1); }, 300);
      }
    }

    // Start trying once the DOM is ready; retry up to 10 times (3 seconds total)
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', function () { tryScroll(10); });
    } else {
      setTimeout(function () { tryScroll(10); }, 100);
    }
  })();

  // ── DOM refs ─────────────────────────────────────────────────
  var wrapper, bellBtn, bellIcon, badge, panel, list, markAllBtn;

  // ── IST formatter (improvement 1) ────────────────────────────
  // Converts an ISO 8601 UTC string to IST (UTC+5:30) display string.
  function formatIST(iso) {
    var d = new Date(iso);
    if (isNaN(d)) return iso;
    var ist = new Date(d.getTime() + 5.5 * 60 * 60 * 1000);
    var pad = function (n) { return String(n).padStart(2, '0'); };
    return ist.getUTCFullYear() + '-' +
           pad(ist.getUTCMonth() + 1) + '-' +
           pad(ist.getUTCDate()) + ' ' +
           pad(ist.getUTCHours()) + ':' +
           pad(ist.getUTCMinutes());
  }

  // ── Web Audio notification sound ─────────────────────────────
  function playNotificationSound() {
    try {
      var ctx = new (window.AudioContext || window.webkitAudioContext)();
      function beep(freq, start, duration, vol) {
        var osc  = ctx.createOscillator();
        var gain = ctx.createGain();
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.type = 'sine';
        osc.frequency.value = freq;
        gain.gain.setValueAtTime(vol, ctx.currentTime + start);
        gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + start + duration);
        osc.start(ctx.currentTime + start);
        osc.stop(ctx.currentTime + start + duration);
      }
      beep(880,  0,    0.12, 0.4);
      beep(1100, 0.13, 0.12, 0.35);
      beep(1320, 0.26, 0.18, 0.3);
    } catch (e) { /* audio not available */ }
  }

  // ── Badge ────────────────────────────────────────────────────
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

  // ── Render the notification items (improvements 2, 3, 4) ──────
  function renderList(notifications) {
    if (!list) return;

    var unread = notifications.filter(function (n) { return !n.read; });
    var read   = notifications.filter(function (n) { return  n.read; });

    if (!notifications.length) {
      list.innerHTML = '<div class="nb-empty">No notifications yet.</div>';
      return;
    }

    list.innerHTML = '';

    // Render unread items
    if (!unread.length) {
      var empty = document.createElement('div');
      empty.className = 'nb-empty';
      empty.textContent = 'No new notifications.';
      list.appendChild(empty);
    } else {
      unread.forEach(function (n) { list.appendChild(buildItem(n)); });
    }

    // Render read items with toggle (improvement 4)
    if (read.length) {
      var readSection = document.createElement('div');
      readSection.id = 'nb-read-section';
      readSection.style.display = readVisible ? 'block' : 'none';
      read.forEach(function (n) { readSection.appendChild(buildItem(n)); });
      list.appendChild(readSection);

      var toggleBtn = document.createElement('button');
      toggleBtn.className = 'nb-toggle-read';
      toggleBtn.id = 'nb-toggle-read-btn';
      updateToggleLabel(toggleBtn, read.length);
      toggleBtn.addEventListener('click', function (e) {
        e.stopPropagation();
        readVisible = !readVisible;
        readSection.style.display = readVisible ? 'block' : 'none';
        updateToggleLabel(toggleBtn, read.length);
      });
      list.appendChild(toggleBtn);
    }
  }

  function updateToggleLabel(btn, count) {
    btn.textContent = readVisible
      ? '▲ Hide read (' + count + ')'
      : '▼ Show read (' + count + ')';
  }

  // ── Build a single notification item (improvements 2 & 3) ────
  function buildItem(n) {
    var item = document.createElement('a');
    item.href = n.url;
    item.className = 'nb-item' + (n.read ? '' : ' nb-unread');
    item.setAttribute('data-id', n.id);
    item.setAttribute('data-read', n.read ? '1' : '0');

    // improvement 2: show note preview
    var previewHtml = n.note_preview
      ? '<span class="nb-item-preview">' + escapeHtml(n.note_preview) + '</span>'
      : '';

    item.innerHTML =
      '<span class="nb-item-subject">#' + n.issue_id + ' – ' + escapeHtml(n.issue_subject) + '</span>' +
      previewHtml +
      '<span class="nb-item-meta">' +
        '<span class="nb-item-author">Mentioned by ' + escapeHtml(n.author_name) + '</span>' +
        '<span class="nb-item-time">' + formatIST(n.created_at) + '</span>' +  // improvement 1
      '</span>';

    item.addEventListener('click', function (e) {
      e.preventDefault();

      if (item.getAttribute('data-read') === '0') {
        markRead(n.id, item);
      }
      closePanel();

      // Split URL into path+query and hash parts (e.g. "/issues/88672" + "#note-3")
      var hashIndex = n.url.indexOf('#');
      var urlPath   = hashIndex >= 0 ? n.url.slice(0, hashIndex) : n.url;
      var urlHash   = hashIndex >= 0 ? n.url.slice(hashIndex)    : '';

      var onSameIssue = window.location.pathname === '/issues/' + n.issue_id;
      var sep = urlPath.indexOf('?') >= 0 ? '&' : '?';
      // Always append _nb so the scroll-to-note script runs after page load.
      // For same-page this also forces a full reload to show the latest content.
      window.location.href = urlPath + sep + '_nb=' + n.id + urlHash;
    });

    return item;
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
        fetchNotifications(); // re-render so read items move to hidden section
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
        if (wrapper) wrapper.style.display = 'none';
        return;
      }
      if (xhr.status === 200) {
        try {
          var data  = JSON.parse(xhr.responseText);
          var count = data.unread_count || 0;
          if (prevUnreadCount !== -1 && count > prevUnreadCount) {
            if (SOUND_ENABLED) playNotificationSound();
            ringBell();
            if (isPanelOpen()) fetchNotifications();
          }
          updateBadge(count);
          prevUnreadCount = count;
        } catch (e) { /* ignore */ }
      }
    };
    xhr.onerror = function () { /* network error */ };
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

  // ── Position widget next to the search box ───────────────────
  function positionBellWidget() {
    if (!wrapper) return;
    var searchForm =
      document.querySelector('#search-form') ||
      document.querySelector('form[action*="search"]') ||
      document.querySelector('#header form') ||
      document.querySelector('.quick-search');

    if (searchForm && searchForm.parentNode) {
      searchForm.parentNode.insertBefore(wrapper, searchForm);
      wrapper.style.display = 'inline-flex';
    } else {
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

    if (!wrapper) return;

    positionBellWidget();

    bellBtn.addEventListener('click', function (e) {
      e.stopPropagation();
      isPanelOpen() ? closePanel() : openPanel();
    });

    if (markAllBtn) {
      markAllBtn.addEventListener('click', function (e) {
        e.stopPropagation();
        markAllRead();
      });
    }

    document.addEventListener('click', function (e) {
      if (wrapper && !wrapper.contains(e.target)) closePanel();
    });

    pollCount();
    setInterval(pollCount, POLL_INTERVAL_MS);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
