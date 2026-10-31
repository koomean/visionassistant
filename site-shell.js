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
})();
