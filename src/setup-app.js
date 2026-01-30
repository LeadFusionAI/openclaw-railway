// Served at /setup/app.js
// Client-side JavaScript for the Moltbot setup wizard

(function () {
  var statusEl = document.getElementById('status');
  var authGroupEl = document.getElementById('authGroup');
  var authChoiceEl = document.getElementById('authChoice');
  var logEl = document.getElementById('log');
  var coreStatusEl = document.getElementById('coreStatus');
  var coreCommitsEl = document.getElementById('coreCommits');

  function setStatus(s) {
    statusEl.textContent = s;
  }

  function renderAuth(groups) {
    authGroupEl.innerHTML = '';
    for (var i = 0; i < groups.length; i++) {
      var g = groups[i];
      var opt = document.createElement('option');
      opt.value = g.value;
      opt.textContent = g.label + (g.hint ? ' - ' + g.hint : '');
      authGroupEl.appendChild(opt);
    }

    authGroupEl.onchange = function () {
      var sel = null;
      for (var j = 0; j < groups.length; j++) {
        if (groups[j].value === authGroupEl.value) sel = groups[j];
      }
      authChoiceEl.innerHTML = '';
      var opts = (sel && sel.options) ? sel.options : [];
      for (var k = 0; k < opts.length; k++) {
        var o = opts[k];
        var opt2 = document.createElement('option');
        opt2.value = o.value;
        opt2.textContent = o.label + (o.hint ? ' - ' + o.hint : '');
        authChoiceEl.appendChild(opt2);
      }
    };

    authGroupEl.onchange();
  }

  function httpJson(url, opts) {
    opts = opts || {};
    opts.credentials = 'same-origin';
    return fetch(url, opts).then(function (res) {
      if (!res.ok) {
        return res.text().then(function (t) {
          throw new Error('HTTP ' + res.status + ': ' + (t || res.statusText));
        });
      }
      return res.json();
    });
  }

  function renderCoreStatus(coreSync) {
    if (!coreSync) {
      coreStatusEl.textContent = 'Core sync not available';
      return;
    }

    var parts = [];

    if (coreSync.initialized) {
      parts.push('Initialized');
    } else {
      parts.push('Not initialized');
    }

    if (coreSync.repoConfigured) {
      parts.push('Repo: configured');
    } else {
      parts.push('Repo: not configured (set CORE_REPO)');
    }

    if (coreSync.tokenConfigured) {
      parts.push('Token: configured');
    } else {
      parts.push('Token: not configured (set GITHUB_TOKEN)');
    }

    if (coreSync.lastSyncTime) {
      parts.push('Last sync: ' + coreSync.lastSyncTime);
    }

    if (coreSync.lastSyncStatus) {
      parts.push('Status: ' + coreSync.lastSyncStatus);
    }

    coreStatusEl.innerHTML = parts.map(function(p) {
      return '<div>' + p + '</div>';
    }).join('');
  }

  function renderCoreCommits(commits) {
    if (!commits || commits.length === 0) {
      coreCommitsEl.innerHTML = '';
      return;
    }

    var html = '<div style="margin-top: 0.5rem; font-size: 0.875rem;"><strong>Recent commits:</strong></div>';
    html += '<ul style="margin: 0.25rem 0; padding-left: 1.5rem; font-size: 0.75rem; color: #888;">';
    for (var i = 0; i < commits.length; i++) {
      var c = commits[i];
      html += '<li>' + escapeHtml(c.subject) + ' <span style="color:#666;">(' + c.date.split(' ')[0] + ')</span></li>';
    }
    html += '</ul>';
    coreCommitsEl.innerHTML = html;
  }

  function escapeHtml(text) {
    var div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  function refreshCoreStatus() {
    httpJson('/setup/api/core/status')
      .then(function(j) {
        renderCoreStatus(j);
        if (j.recentCommits) {
          renderCoreCommits(j.recentCommits);
        }
      })
      .catch(function(e) {
        coreStatusEl.textContent = 'Error: ' + String(e);
      });
  }

  function refreshStatus() {
    setStatus('Loading...');
    return httpJson('/setup/api/status').then(function (j) {
      var ver = j.moltbotVersion ? (' | ' + j.moltbotVersion) : '';
      var securityInfo = '';

      if (j.security) {
        var checks = [];
        if (j.security.setupPasswordSet) checks.push('password');
        if (j.security.gatewayTokenSet) checks.push('token');
        if (j.security.nonRootUser) checks.push('non-root');
        securityInfo = ' | Security: ' + checks.join(', ');
      }

      setStatus((j.configured ? 'Configured - open /moltbot' : 'Not configured - run setup below') + ver + securityInfo);
      renderAuth(j.authGroups || []);

      // Render Core sync status from main status
      if (j.coreSync) {
        renderCoreStatus(j.coreSync);
      }

      if (j.channelsAddHelp && j.channelsAddHelp.indexOf('telegram') === -1) {
        logEl.textContent += '\nNote: this moltbot build does not list telegram in `channels add --help`. Telegram auto-add will be skipped.\n';
      }

    }).catch(function (e) {
      setStatus('Error: ' + String(e));
    });
  }

  document.getElementById('run').onclick = function () {
    var payload = {
      flow: document.getElementById('flow').value,
      authChoice: authChoiceEl.value,
      authSecret: document.getElementById('authSecret').value,
      telegramToken: document.getElementById('telegramToken').value,
      discordToken: document.getElementById('discordToken').value,
      slackBotToken: document.getElementById('slackBotToken').value,
      slackAppToken: document.getElementById('slackAppToken').value
    };

    logEl.textContent = 'Running setup with hardened defaults...\n';
    logEl.textContent += '- Command execution: DISABLED\n';
    logEl.textContent += '- Gateway auth: TOKEN\n';
    logEl.textContent += '- Trusted proxies: CONFIGURED\n\n';

    fetch('/setup/api/run', {
      method: 'POST',
      credentials: 'same-origin',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(payload)
    }).then(function (res) {
      return res.text();
    }).then(function (text) {
      var j;
      try { j = JSON.parse(text); } catch (_e) { j = { ok: false, output: text }; }
      logEl.textContent += (j.output || JSON.stringify(j, null, 2));
      return refreshStatus();
    }).catch(function (e) {
      logEl.textContent += '\nError: ' + String(e) + '\n';
    });
  };

  // Pairing approve helper
  var pairingBtn = document.getElementById('pairingApprove');
  if (pairingBtn) {
    pairingBtn.onclick = function () {
      var channel = prompt('Enter channel (telegram or discord):');
      if (!channel) return;
      channel = channel.trim().toLowerCase();
      if (channel !== 'telegram' && channel !== 'discord') {
        alert('Channel must be "telegram" or "discord"');
        return;
      }
      var code = prompt('Enter pairing code (e.g. 3EY4PUYS):');
      if (!code) return;
      logEl.textContent += '\nApproving pairing for ' + channel + '...\n';
      fetch('/setup/api/pairing/approve', {
        method: 'POST',
        credentials: 'same-origin',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ channel: channel, code: code.trim() })
      }).then(function (r) { return r.text(); })
        .then(function (t) { logEl.textContent += t + '\n'; })
        .catch(function (e) { logEl.textContent += 'Error: ' + String(e) + '\n'; });
    };
  }

  document.getElementById('reset').onclick = function () {
    if (!confirm('Reset setup? This deletes the config file so onboarding can run again.')) return;
    logEl.textContent = 'Resetting...\n';
    fetch('/setup/api/reset', { method: 'POST', credentials: 'same-origin' })
      .then(function (res) { return res.text(); })
      .then(function (t) { logEl.textContent += t + '\n'; return refreshStatus(); })
      .catch(function (e) { logEl.textContent += 'Error: ' + String(e) + '\n'; });
  };

  // Core sync buttons
  var coreInitBtn = document.getElementById('coreInit');
  if (coreInitBtn) {
    coreInitBtn.onclick = function () {
      coreStatusEl.textContent = 'Initializing Core...';
      fetch('/setup/api/core/init', {
        method: 'POST',
        credentials: 'same-origin',
        headers: { 'content-type': 'application/json' }
      }).then(function (res) { return res.json(); })
        .then(function (j) {
          if (j.success) {
            coreStatusEl.textContent = 'Core initialized successfully!';
            refreshCoreStatus();
          } else {
            coreStatusEl.textContent = 'Error: ' + (j.error || 'Unknown error');
          }
        })
        .catch(function (e) {
          coreStatusEl.textContent = 'Error: ' + String(e);
        });
    };
  }

  var coreSyncBtn = document.getElementById('coreSync');
  if (coreSyncBtn) {
    coreSyncBtn.onclick = function () {
      coreStatusEl.textContent = 'Syncing Core...';
      fetch('/setup/api/core/sync', {
        method: 'POST',
        credentials: 'same-origin',
        headers: { 'content-type': 'application/json' }
      }).then(function (res) { return res.json(); })
        .then(function (j) {
          if (j.success) {
            var msg = 'Sync complete!';
            if (j.pulled) msg += ' Pulled updates.';
            if (j.pushed) msg += ' Pushed changes.';
            if (j.conflicts && j.conflicts.length > 0) {
              msg += ' Conflicts resolved: ' + j.conflicts.join(', ');
            }
            coreStatusEl.textContent = msg;
            refreshCoreStatus();
          } else {
            coreStatusEl.textContent = 'Error: ' + (j.error || 'Unknown error');
          }
        })
        .catch(function (e) {
          coreStatusEl.textContent = 'Error: ' + String(e);
        });
    };
  }

  refreshStatus();
  // Also fetch detailed Core status with commits
  setTimeout(refreshCoreStatus, 500);
})();
