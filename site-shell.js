/* Copyright (C) 2026 Wachirawich Kripindakul. SPDX-License-Identifier: AGPL-3.0-or-later. See LICENSE. */
(() => {
  'use strict';
  const root = document.documentElement;
  const header = document.querySelector('.site-header');
  const toggle = header?.querySelector('.menu-toggle');
  const navigation = header?.querySelector('#navigation');
  if (!header || !toggle || !navigation) return;
  root.classList.add('navigation-ready');
  const more = navigation.querySelector('.nav-more');
  const moreToggle = more?.querySelector('.nav-more-toggle');
  const morePanel = more?.querySelector('.nav-more-panel');
  function setMore(open, focus = false) {
    if (!moreToggle || !morePanel) return;
    moreToggle.setAttribute('aria-expanded', String(open));
    morePanel.hidden = !open;
    if (open && focus) morePanel.querySelector('a')?.focus();
  }
  function setMenu(open) {
    toggle.setAttribute('aria-expanded', String(open));
    header.classList.toggle('menu-open', open);
    navigation.classList.toggle('is-open', open);
    if (!open) setMore(false);
  }
  moreToggle?.addEventListener('click', () => setMore(moreToggle.getAttribute('aria-expanded') !== 'true'));
  moreToggle?.addEventListener('keydown', event => {
    if (event.key === 'ArrowDown') { event.preventDefault(); setMore(true, true); }
  });
  more?.addEventListener('focusout', event => { if (!more.contains(event.relatedTarget)) setMore(false); });
  toggle.addEventListener('click', event => {
    const open = toggle.getAttribute('aria-expanded') !== 'true';
    setMenu(open);
    if (open && event.detail === 0) navigation.querySelector('a')?.focus();
  });
  navigation.addEventListener('click', event => { if (event.target.closest('a')) setMenu(false); });
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && moreToggle?.getAttribute('aria-expanded') === 'true') { setMore(false); moreToggle.focus(); return; }
    if (event.key === 'Escape' && toggle.getAttribute('aria-expanded') === 'true') { setMenu(false); toggle.focus(); }
  });
  document.addEventListener('click', event => {
    if (!more?.contains(event.target)) setMore(false);
    if (!header.contains(event.target)) setMenu(false);
  });
  matchMedia('(min-width: 1051px)').addEventListener('change', () => setMenu(false));
  function updateLinks() {
    const language = root.lang === 'en' ? 'en' : 'th';
    const home = location.pathname === '/' || location.pathname === '/index.html';
    document.querySelectorAll('[data-home-anchor]').forEach(link => {
      const anchor = link.dataset.homeAnchor;
      link.setAttribute('href', home ? `#${anchor}` : `/?lang=${language}#${anchor}`);
    });
    document.querySelectorAll('[data-secondary-link]').forEach(link => {
      const url = new URL(link.getAttribute('href'), location.href);
      url.searchParams.set('lang', language);
      link.href = url.pathname + url.search + url.hash;
      const current = url.pathname === location.pathname;
      if (current) link.setAttribute('aria-current', 'page');
      else link.removeAttribute('aria-current');
    });
    moreToggle?.classList.toggle('is-current', Boolean(morePanel?.querySelector('[aria-current="page"]')));
  }
  window.addEventListener('lunav:languagechange', updateLinks);
  updateLinks();
  function updateHeader() { header.classList.toggle('scrolled', scrollY > 20); }
  window.addEventListener('scroll', updateHeader, { passive: true });
  updateHeader();

  // iOS Safari may expose document pixels above a fixed header even when its
  // safe-area inset is zero. Remove that offscreen paint without changing layout,
  // native scrolling, or sticky section positions.
  const surfaces = [...document.querySelectorAll('main,.site-footer,.document-footer,.contact-footer,.lost-footer')];
  const clips = new WeakMap();
  let paintFrame = 0;
  function updatePagePaint() {
    paintFrame = 0;
    const edge = header.getBoundingClientRect().bottom;
    const updates = surfaces.map(node => {
      const rect = node.getBoundingClientRect();
      return [node, `${Math.max(0, Math.min(rect.height, edge - rect.top)).toFixed(2)}px`];
    });
    for (const [node, clip] of updates) {
      if (clips.get(node) === clip) continue;
      node.style.setProperty('--header-clip-top', clip);
      clips.set(node, clip);
    }
  }
  function schedulePagePaint() {
    if (!paintFrame) paintFrame = requestAnimationFrame(updatePagePaint);
  }
  window.addEventListener('scroll', schedulePagePaint, { passive: true });
  window.addEventListener('resize', schedulePagePaint, { passive: true });
  window.addEventListener('load', schedulePagePaint);
  window.addEventListener('pageshow', schedulePagePaint);
  window.addEventListener('afterprint', schedulePagePaint);
  window.addEventListener('lunav:languagechange', schedulePagePaint);
  window.visualViewport?.addEventListener('resize', schedulePagePaint, { passive: true });
  window.visualViewport?.addEventListener('scroll', schedulePagePaint, { passive: true });
  window.addEventListener('pagehide', () => {
    cancelAnimationFrame(paintFrame);
    paintFrame = 0;
  });
  if ('ResizeObserver' in window) {
    const observer = new ResizeObserver(schedulePagePaint);
    [header, ...surfaces].forEach(node => observer.observe(node));
  }
  document.fonts?.ready.then(schedulePagePaint);
  updatePagePaint();
})();
