/* Copyright (C) 2026 Wachirawich Kripindakul. SPDX-License-Identifier: AGPL-3.0-or-later. See LICENSE. */
(() => {
  'use strict';
  const root = document.documentElement;
  const motion = matchMedia('(prefers-reduced-motion: reduce)');
  const key = 'lunav-page-transition';
  const contact = path => path === '/contact.html';
  const pages = new Set(['/', '/index.html', '/contact.html', '/project-status.html', '/licensing.html', '/credits.html', '/resources.html', '/lunavision-architecture.html', '/404.html']);
  let departing = false, navigationTimer, resetTimer, arrivalFrame;
  let direction = root.dataset.pageTransitionDirection || 'outbound';
  let cancelPositioning = () => {};
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
  function label(language, nextDirection = direction) {
    direction = nextDirection;
    const english = language === 'en';
    root.dataset.pageTransitionLabel = direction === 'return'
      ? (english ? 'Taking you back to the stars' : 'กำลังพากลับสู่ดวงดาว')
      : (english ? 'Finding a path to the stars' : 'กำลังหาเส้นทางไปยังดวงดาว');
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
    cancelAnimationFrame(arrivalFrame);
    cancelPositioning();
    delete root.dataset.pageTransitionManaged;
    departing = false;
    root.classList.remove('page-leaving', 'page-arriving', 'page-arrival-reveal', 'page-positioning');
    status.setAttribute('aria-hidden', 'true');
  }
  function reveal() {
    arrivalFrame = requestAnimationFrame(() => {
      arrivalFrame = requestAnimationFrame(() => {
        root.classList.add('page-arrival-reveal');
        clearTimeout(resetTimer);
        resetTimer = setTimeout(reset, 280);
      });
    });
  }
  function positionHome() {
    const controller = new AbortController();
    let cancelled = false, positioning = false, frame, deadlineTimer;
    let previousTop, stableFrames = 0;
    const deadline = performance.now() + 2500;
    function cleanup() {
      cancelled = true;
      controller.abort();
      cancelAnimationFrame(frame);
      clearTimeout(deadlineTimer);
    }
    cancelPositioning = cleanup;
    // A deliberate scroll or navigation takes control immediately.
    for (const type of ['wheel', 'touchstart', 'pointerdown']) {
      window.addEventListener(type, reset, { passive: true, signal: controller.signal });
    }
    window.addEventListener('keydown', event => {
      if (['Escape', 'ArrowUp', 'ArrowDown', 'PageUp', 'PageDown', 'Home', 'End', ' '].includes(event.key)) reset();
    }, { signal: controller.signal });
    window.addEventListener('popstate', reset, { signal: controller.signal });
    function destinationTop() {
      let target;
      try { target = document.getElementById(decodeURIComponent(location.hash.slice(1))); } catch {}
      const padding = parseFloat(getComputedStyle(root).scrollPaddingTop) || 0;
      const top = target ? target.getBoundingClientRect().top + scrollY - padding : 0;
      return Math.max(0, Math.min(top, root.scrollHeight - innerHeight));
    }
    function align() {
      if (cancelled) return;
      const top = destinationTop();
      // Cancel native smooth hash scrolling while the opaque curtain is up.
      window.scrollTo({ top, behavior: 'auto' });
      stableFrames = previousTop !== undefined && Math.abs(top - previousTop) < 1 && Math.abs(scrollY - top) < 1
        ? stableFrames + 1 : 0;
      previousTop = top;
      if (stableFrames >= 3 || performance.now() >= deadline) {
        cleanup();
        reveal();
      } else frame = requestAnimationFrame(align);
    }
    function begin() {
      if (cancelled || positioning) return;
      positioning = true;
      align();
    }
    function parsed() {
      // DOMContentLoaded follows homepage translation and other deferred scripts.
      // Fonts can change section heights, so position only after their layout settles.
      Promise.resolve(document.fonts?.ready).then(begin, begin);
    }
    if (document.readyState === 'complete') parsed();
    else document.addEventListener('DOMContentLoaded', parsed, { once: true, signal: controller.signal });
    // One bound covers all dependencies; a failed resource cannot trap the visitor.
    deadlineTimer = setTimeout(() => {
      if (cancelled) return;
      window.scrollTo({ top: destinationTop(), behavior: 'auto' });
      cleanup();
      reveal();
    }, 2500);
  }
  if (root.classList.contains('page-arriving')) {
    status.setAttribute('aria-hidden', 'false');
    // The head watchdog hands over to this bounded arrival lifecycle.
    resetTimer = setTimeout(reset, 3200);
    root.dataset.pageTransitionManaged = 'true';
    const restoringHistory = performance.getEntriesByType('navigation')[0]?.type === 'back_forward';
    if (root.dataset.pageTransitionReturnHome === 'true' && !restoringHistory) positionHome();
    else reveal();
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
    cancelAnimationFrame(arrivalFrame);
    cancelPositioning();
    departing = true;
    label(root.lang, contact(url.pathname) ? 'outbound' : 'return');
    status.setAttribute('aria-hidden', 'false');
    clearTimeout(resetTimer);
    root.classList.remove('page-arriving', 'page-arrival-reveal', 'page-positioning');
    root.classList.add('page-leaving');
    try { sessionStorage.setItem(key, JSON.stringify({ to: url.href, time: Date.now(), direction })); } catch { /* Ordinary navigation works without storage. */ }
    // Let the short status settle into view before the next document replaces it.
    navigationTimer = setTimeout(() => {
      location.assign(url.href);
    }, 360);
    // A cancelled or failed navigation must not leave a curtain over the page.
    resetTimer = setTimeout(reset, 2200);
  });
  window.addEventListener('pageshow', event => { if (event.persisted) reset(); });
  window.addEventListener('pagehide', reset);
  window.addEventListener('beforeprint', reset);
  document.addEventListener('keydown', event => { if (event.key === 'Escape' && departing) reset(); });
  document.addEventListener('visibilitychange', () => { if (document.hidden && !departing) reset(); });
  window.addEventListener('lunav:languagechange', event => label(event.detail?.language || root.lang));
  function updateMotion() {
    if (!reduced()) return;
    if (!departing) reset();
    else {
      // Keep a requested navigation, but remove its visual motion immediately.
      cancelAnimationFrame(arrivalFrame);
      cancelPositioning();
      root.classList.remove('page-leaving', 'page-arriving', 'page-arrival-reveal', 'page-positioning');
      status.setAttribute('aria-hidden', 'true');
    }
  }
  motion.addEventListener('change', updateMotion);
  window.addEventListener('storage', event => { if (event.key === 'lunav-reduce-motion') updateMotion(); });
  window.addEventListener('lunav:motionchange', updateMotion);
})();
