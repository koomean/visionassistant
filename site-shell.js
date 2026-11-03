/* Copyright (C) 2026 Wachirawich Kripindakul. SPDX-License-Identifier: AGPL-3.0-or-later. See LICENSE. */
(() => {
  'use strict';
  const root = document.documentElement;
  const header = document.querySelector('.site-header');
  const toggle = header?.querySelector('.menu-toggle');
  const navigation = header?.querySelector('#navigation');
  if (!header || !toggle || !navigation) return;
  root.classList.add('navigation-ready');
  function setMenu(open) {
    toggle.setAttribute('aria-expanded', String(open));
    header.classList.toggle('menu-open', open);
    navigation.classList.toggle('is-open', open);
  }
  toggle.addEventListener('click', event => {
    const open = toggle.getAttribute('aria-expanded') !== 'true';
    setMenu(open);
    if (open && event.detail === 0) navigation.querySelector('a')?.focus();
  });
  navigation.addEventListener('click', event => { if (event.target.closest('a')) setMenu(false); });
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && toggle.getAttribute('aria-expanded') === 'true') { setMenu(false); toggle.focus(); }
  });
  document.addEventListener('click', event => { if (!header.contains(event.target)) setMenu(false); });
  matchMedia('(min-width: 881px)').addEventListener('change', event => { if (event.matches) setMenu(false); });
  function updateLinks() {
    const language = root.lang === 'en' ? 'en' : 'th';
    const home = location.pathname === '/' || location.pathname === '/index.html';
    document.querySelectorAll('[data-home-anchor]').forEach(link => {
      const anchor = link.dataset.homeAnchor;
      link.setAttribute('href', home ? `#${anchor}` : `/?lang=${language}#${anchor}`);
    });
  }
  window.addEventListener('lunav:languagechange', updateLinks);
  updateLinks();

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
