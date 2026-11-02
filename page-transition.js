/* Copyright (C) 2026 Wachirawich Kripindakul. SPDX-License-Identifier: AGPL-3.0-or-later. See LICENSE. */
(() => {
  'use strict';
  const root = document.documentElement;
  const motion = matchMedia('(prefers-reduced-motion: reduce)');
  const key = 'lunav-page-transition';
  const contact = path => path === '/contact.html';
  const pages = new Set(['/', '/index.html', '/contact.html', '/project-status.html', '/licensing.html', '/credits.html', '/404.html']);
  let departing = false, navigationTimer, resetTimer;
  function reduced() {
    try { return motion.matches || localStorage.getItem('lunav-reduce-motion') === 'true'; }
    catch { return motion.matches; }
  }
  function reset() {
    clearTimeout(navigationTimer);
    clearTimeout(resetTimer);
    departing = false;
    root.classList.remove('page-leaving', 'page-arriving', 'page-arrival-reveal');
  }
  if (root.classList.contains('page-arriving')) {
    // The head bootstrap covers the first paint. Reveal the fully parsed page.
    requestAnimationFrame(() => requestAnimationFrame(() => {
      root.classList.add('page-arrival-reveal');
      resetTimer = setTimeout(reset, 280);
    }));
  }
  document.addEventListener('click', event => {
    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || reduced()) return;
    const link = event.target.closest('a[href]');
    if (!link || link.hasAttribute('download') || (link.target && link.target !== '_self')) return;
    const url = new URL(link.href, location.href);
    if (url.origin !== location.origin || !pages.has(url.pathname) || (!contact(location.pathname) && !contact(url.pathname))) return;
    if (url.pathname === location.pathname && url.search === location.search) return;
    event.preventDefault();
    if (departing) return;
    departing = true;
    clearTimeout(resetTimer);
    root.classList.remove('page-arriving', 'page-arrival-reveal');
    root.classList.add('page-leaving');
    try { sessionStorage.setItem(key, JSON.stringify({ to: url.href, time: Date.now() })); } catch { /* Ordinary navigation works without storage. */ }
    navigationTimer = setTimeout(() => location.assign(url.href), 180);
    // A cancelled or failed navigation must not leave a curtain over the page.
    resetTimer = setTimeout(reset, 2200);
  });
  window.addEventListener('pageshow', event => { if (event.persisted) reset(); });
  window.addEventListener('pagehide', () => { clearTimeout(navigationTimer); clearTimeout(resetTimer); });
  window.addEventListener('beforeprint', reset);
  motion.addEventListener('change', () => { if (motion.matches && !departing) reset(); });
})();
