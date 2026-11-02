/* Copyright (C) 2026 Wachirawich Kripindakul. SPDX-License-Identifier: AGPL-3.0-or-later. See LICENSE. */
(() => {
  'use strict';
  const root = document.documentElement;
  const motion = matchMedia('(prefers-reduced-motion: reduce)');
  const key = 'lunav-page-transition';
  const contact = path => path === '/contact.html';
  const pages = new Set(['/', '/index.html', '/contact.html', '/project-status.html', '/licensing.html', '/credits.html', '/404.html']);
  let departing = false, navigationTimer, resetTimer;
  const status = document.createElement('div');
  status.className = 'page-transition-status';
  status.setAttribute('role', 'status');
  status.setAttribute('aria-live', 'polite');
  status.setAttribute('aria-atomic', 'true');
  status.setAttribute('aria-hidden', 'true');
  const orbit = document.createElement('span');
  orbit.className = 'page-transition-orbit';
  orbit.setAttribute('aria-hidden', 'true');
  const message = document.createElement('span');
  message.className = 'page-transition-message';
  status.append(orbit, message);
  document.body.append(status);
  function label(language) {
    const english = language === 'en';
    root.dataset.pageTransitionLabel = english ? 'Finding a path to the stars' : 'กำลังหาเส้นทางไปยังดวงดาว';
    status.lang = english ? 'en' : 'th';
    message.textContent = root.dataset.pageTransitionLabel;
  }
  // The head already knows the destination language before homepage translation runs.
  label(root.dataset.pageTransitionLanguage || root.lang);
  root.classList.add('page-transition-ready');
  function reduced() {
    try { return motion.matches || localStorage.getItem('lunav-reduce-motion') === 'true'; }
    catch { return motion.matches; }
  }
  function reset() {
    clearTimeout(navigationTimer);
    clearTimeout(resetTimer);
    departing = false;
    root.classList.remove('page-leaving', 'page-arriving', 'page-arrival-reveal');
    status.setAttribute('aria-hidden', 'true');
  }
  if (root.classList.contains('page-arriving')) {
    status.setAttribute('aria-hidden', 'false');
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
    label(root.lang);
    status.setAttribute('aria-hidden', 'false');
    clearTimeout(resetTimer);
    root.classList.remove('page-arriving', 'page-arrival-reveal');
    root.classList.add('page-leaving');
    try { sessionStorage.setItem(key, JSON.stringify({ to: url.href, time: Date.now() })); } catch { /* Ordinary navigation works without storage. */ }
    // Let the short status settle into view before the next document replaces it.
    navigationTimer = setTimeout(() => {
      location.assign(url.href);
    }, 360);
    // A cancelled or failed navigation must not leave a curtain over the page.
    resetTimer = setTimeout(reset, 2200);
  });
  window.addEventListener('pageshow', event => { if (event.persisted) reset(); });
  window.addEventListener('pagehide', () => { clearTimeout(navigationTimer); clearTimeout(resetTimer); });
  window.addEventListener('beforeprint', reset);
  document.addEventListener('keydown', event => { if (event.key === 'Escape' && departing) reset(); });
  document.addEventListener('visibilitychange', () => { if (document.hidden && !departing) reset(); });
  window.addEventListener('lunav:languagechange', event => label(event.detail?.language || root.lang));
  function updateMotion() {
    if (!reduced()) return;
    if (!departing) reset();
    else {
      // Keep a requested navigation, but remove its visual motion immediately.
      root.classList.remove('page-leaving', 'page-arriving', 'page-arrival-reveal');
      status.setAttribute('aria-hidden', 'true');
    }
  }
  motion.addEventListener('change', updateMotion);
  window.addEventListener('storage', event => { if (event.key === 'lunav-reduce-motion') updateMotion(); });
  window.addEventListener('lunav:motionchange', updateMotion);
})();
