/* Copyright (C) 2026 Wachirawich Kripindakul. SPDX-License-Identifier: AGPL-3.0-or-later. See LICENSE. */
(() => {
  'use strict';
  const root = document.documentElement;
  root.classList.add('js');
  const safeStorage = {
    get(key) { try { return localStorage.getItem(key); } catch { return null; } },
    set(key, value) { try { localStorage.setItem(key, value); } catch { /* Private browsing may deny storage. */ } }
  };
  const translations = [...document.querySelectorAll('[data-en]')].map(el => ({ el, th: el.textContent, en: el.dataset.en }));
  const attributes = ['aria-label', 'alt'].flatMap(attr => {
    const key = attr === 'alt' ? 'data-en-alt' : 'data-en-aria';
    return [...document.querySelectorAll(`[${key}]`)].map(el => ({ el, attr, th: el.getAttribute(attr), en: el.getAttribute(key) }));
  });
  const metadata = {
    th: { title: 'LunaV — แสงเล็ก ๆ เพื่อโลกที่ชัดขึ้น', description: 'LunaV ผู้ช่วยมองภาพบน iPhone ถามด้วยเสียง อ่านและฟังคำตอบ วัดระยะด้วย LiDAR หรือประมาณจาก Depth Anything 3 ประมวลผลบนเครื่อง โปรเจกต์วิจัย SCiUS Forums 17', locale: 'th_TH' },
    en: { title: 'LunaV — A little light. A clearer world.', description: 'Meet LunaV, an on-device iPhone vision research prototype. Ask in your selected Thai or English language, hear Apple-voice answers, and explore LiDAR or DA3 distance estimates. Initial speech-language setup may require an Apple download.', locale: 'en_US' }
  };
  let language = 'th';
  function setLanguage(next, persist = false) {
    language = next === 'en' ? 'en' : 'th';
    root.lang = language;
    translations.forEach(item => { item.el.textContent = item[language]; });
    attributes.forEach(item => { item.el.setAttribute(item.attr, item[language]); });
    document.querySelectorAll('[data-language]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.language === language)));
    document.title = metadata[language].title;
    const description = document.querySelector('meta[name="description"]');
    if (description) description.content = metadata[language].description;
    document.querySelector('meta[property="og:title"]')?.setAttribute('content', metadata[language].title);
    document.querySelector('meta[property="og:description"]')?.setAttribute('content', metadata[language].description);
    document.querySelector('meta[property="og:locale"]')?.setAttribute('content', metadata[language].locale);
    if (persist) safeStorage.set('lunav-language', language);
    requestRender();
    requestAnimationFrame(updateTabMarker);
  }
  document.querySelectorAll('[data-language]').forEach(button => button.addEventListener('click', () => setLanguage(button.dataset.language, true)));

  const header = document.querySelector('.site-header');
  const menuToggle = document.querySelector('.menu-toggle');
  const navigation = document.querySelector('#navigation');
  function setMenu(open) {
    menuToggle?.setAttribute('aria-expanded', String(open));
    header?.classList.toggle('menu-open', open);
    navigation?.classList.toggle('is-open', open);
  }
  menuToggle?.addEventListener('click', () => setMenu(menuToggle.getAttribute('aria-expanded') !== 'true'));
  navigation?.querySelectorAll('a').forEach(link => link.addEventListener('click', () => setMenu(false)));
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && menuToggle?.getAttribute('aria-expanded') === 'true') { setMenu(false); menuToggle.focus(); }
  });
  document.addEventListener('click', event => { if (!header?.contains(event.target)) setMenu(false); });
  matchMedia('(min-width: 881px)').addEventListener('change', event => { if (event.matches) setMenu(false); });

  const tabs = [...document.querySelectorAll('[role="tab"]')];
  const tabList = document.querySelector('.feature-tabs');
  function updateTabMarker() {
    const active = tabs.find(tab => tab.getAttribute('aria-selected') === 'true');
    if (!tabList || !active) return;
    tabList.style.setProperty('--tab-left', `${active.offsetLeft}px`);
    tabList.style.setProperty('--tab-width', `${active.offsetWidth}px`);
  }
  function activateTab(tab, focus = false) {
    tabs.forEach(item => {
      const active = item === tab;
      item.classList.toggle('is-active', active);
      item.setAttribute('aria-selected', String(active));
      item.tabIndex = active ? 0 : -1;
      const panel = document.getElementById(item.getAttribute('aria-controls'));
      if (panel) { panel.classList.toggle('is-active', active); panel.hidden = !active; }
    });
    if (focus) tab.focus();
    updateTabMarker();
    requestRender();
  }
  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => activateTab(tab));
    tab.addEventListener('keydown', event => {
      let next;
      if (event.key === 'ArrowRight') next = (index + 1) % tabs.length;
      if (event.key === 'ArrowLeft') next = (index - 1 + tabs.length) % tabs.length;
      if (event.key === 'Home') next = 0;
      if (event.key === 'End') next = tabs.length - 1;
      if (next !== undefined) { event.preventDefault(); activateTab(tabs[next], true); }
    });
  });

  const systemMotion = matchMedia('(prefers-reduced-motion: reduce)');
  const motionButton = document.querySelector('#motion-toggle');
  let manualReduced = safeStorage.get('lunav-reduce-motion') === 'true';
  let reduced = systemMotion.matches || manualReduced;
  const revealElements = [...document.querySelectorAll('.reveal')];
  let revealObserver;
  if ('IntersectionObserver' in window) {
    revealObserver = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        if (entry.isIntersecting) entry.target.classList.add('is-visible');
        else if (entry.boundingClientRect.top > innerHeight || entry.boundingClientRect.bottom < 0) entry.target.classList.remove('is-visible');
      });
    }, { threshold: 0.06 });
    revealElements.forEach(el => revealObserver.observe(el));
  } else revealElements.forEach(el => el.classList.add('is-visible'));
  function applyMotion() {
    reduced = systemMotion.matches || manualReduced;
    root.classList.toggle('motion-reduced', reduced);
    root.classList.toggle('motion-enabled', !reduced && Boolean(revealObserver));
    motionButton?.setAttribute('aria-pressed', String(reduced));
    if (motionButton) motionButton.disabled = systemMotion.matches;
    if (reduced) { root.style.setProperty('--hero-shift', '0px'); root.style.setProperty('--moon-turn', '0deg'); }
    window.dispatchEvent(new CustomEvent('lunav:motionchange', { detail: { reduced } }));
    requestRender();
  }
  motionButton?.addEventListener('click', () => { manualReduced = !manualReduced; safeStorage.set('lunav-reduce-motion', String(manualReduced)); applyMotion(); });
  systemMotion.addEventListener('change', applyMotion);

  const canvas = document.querySelector('#starfield');
  const context = canvas?.getContext('2d');
  const hero = document.querySelector('.hero');
  const journey = document.querySelector('.journey');
  const privacyArt = document.querySelector('.privacy-art');
  const activePreview = () => document.querySelector('.feature-panel.is-active .app-preview');
  const journeySteps = [...document.querySelectorAll('.journey > li')];
  let width = 0, height = 0, stars = [], frame = 0, ticking = false;
  let visualScroll = Math.max(0, window.scrollY), lastFrame = 0;
  let pageVisible = !document.hidden;
  // A repeatable sky avoids layout changes between visits. Motion is scroll-driven;
  // the sky does not run a continuous animation loop while the page is idle.
  function seeded(seed) { return () => { seed = (seed * 16807) % 2147483647; return (seed - 1) / 2147483646; }; }
  function sizeSky() {
    width = innerWidth; height = innerHeight;
    if (!context) return;
    const dpr = Math.min(devicePixelRatio || 1, 1.8);
    canvas.width = Math.round(width * dpr); canvas.height = Math.round(height * dpr);
    context.setTransform(dpr, 0, 0, dpr, 0, 0);
    const random = seeded(17072026);
    const count = Math.min(160, Math.round(width * height / 7500));
    stars = Array.from({ length: count }, () => ({ x: random() * width, y: random() * height, r: .45 + random() * .9, a: .2 + random() * .6, depth: .07 + random() * .13 }));
    requestRender();
  }
  function drawSky(scroll) {
    if (!context) return;
    context.clearRect(0, 0, width, height);
    for (const star of stars) {
      const y = ((star.y - (reduced ? 0 : scroll * star.depth)) % height + height) % height;
      context.beginPath(); context.arc(star.x, y, star.r, 0, Math.PI * 2);
      context.fillStyle = `rgba(197,211,239,${star.a})`; context.fill();
      if (star.r > 1.2) { context.strokeStyle = `rgba(197,211,239,${star.a * .45})`; context.lineWidth = .5; context.beginPath(); context.moveTo(star.x - 3, y); context.lineTo(star.x + 3, y); context.moveTo(star.x, y - 3); context.lineTo(star.x, y + 3); context.stroke(); }
    }
  }
  function render(timestamp) {
    ticking = false;
    if (!pageVisible) return;
    const scroll = Math.max(0, window.scrollY);
    const delta = lastFrame ? Math.min(64, Math.max(1, timestamp - lastFrame)) : 16.67;
    lastFrame = timestamp;
    const difference = scroll - visualScroll;
    if (reduced || Math.abs(difference) > innerHeight * 2) visualScroll = scroll;
    else visualScroll += difference * (1 - Math.exp(-delta / 85));
    if (Math.abs(scroll - visualScroll) < .15) visualScroll = scroll;
    const maxScroll = document.documentElement.scrollHeight - innerHeight;
    root.style.setProperty('--scroll', maxScroll > 0 ? Math.min(1, scroll / maxScroll).toFixed(4) : '0');
    header?.classList.toggle('scrolled', scroll > 20);
    if (!reduced && hero) {
      const progress = Math.min(1.4, visualScroll / hero.offsetHeight);
      root.style.setProperty('--hero-shift', `${(progress * -55).toFixed(2)}px`);
      root.style.setProperty('--moon-turn', `${(progress * 16).toFixed(2)}deg`);
    }
    if (journey) {
      const rect = journey.getBoundingClientRect();
      const progress = Math.min(1, Math.max(0, (innerHeight * .85 - rect.top) / (rect.height + innerHeight * .25)));
      root.style.setProperty('--journey', reduced ? '1' : progress.toFixed(4));
      journeySteps.forEach((step, index) => step.classList.toggle('is-reached', reduced || progress >= (index + .25) / journeySteps.length));
    }
    if (privacyArt) {
      const rect = privacyArt.getBoundingClientRect();
      const offset = Math.max(-18, Math.min(18, (innerHeight / 2 - (rect.top + rect.height / 2)) * .04));
      privacyArt.style.setProperty('--privacy-shift', reduced ? '0px' : `${offset.toFixed(2)}px`);
    }
    const preview = activePreview();
    if (preview) {
      const rect = preview.getBoundingClientRect();
      const offset = Math.max(-12, Math.min(12, (innerHeight / 2 - (rect.top + rect.height / 2)) * .025));
      preview.style.setProperty('--preview-shift', reduced ? '0px' : `${offset.toFixed(2)}px`);
    }
    drawSky(visualScroll);
    if (!reduced && Math.abs(scroll - visualScroll) > .15) requestRender();
  }
  function requestRender() { if (!ticking) { ticking = true; frame = requestAnimationFrame(render); } }
  window.addEventListener('scroll', requestRender, { passive: true });
  window.addEventListener('resize', () => { sizeSky(); updateTabMarker(); requestRender(); }, { passive: true });
  document.addEventListener('visibilitychange', () => { pageVisible = !document.hidden; if (!pageVisible) { cancelAnimationFrame(frame); ticking = false; } else { lastFrame = 0; requestRender(); } });
  if ('ResizeObserver' in window) new ResizeObserver(requestRender).observe(document.body);
  if ('IntersectionObserver' in window && navigation) {
    const sections = [...document.querySelectorAll('main section[id]')];
    const activeSections = new Set();
    // Observe each real section with a single shared observer.
    const navObserver = new IntersectionObserver(entries => {
      for (const entry of entries) { if (entry.isIntersecting) activeSections.add(entry.target); else activeSections.delete(entry.target); }
      const active = sections.filter(section => activeSections.has(section)).at(-1);
      navigation.querySelectorAll('a').forEach(link => {
        if (active && link.hash === `#${active.id}`) link.setAttribute('aria-current', 'location'); else link.removeAttribute('aria-current');
      });
    }, { rootMargin: '-20% 0px -40% 0px', threshold: 0 });
    sections.forEach(section => navObserver.observe(section));
  }
  const requestedLanguage = new URLSearchParams(location.search).get('lang');
  if (tabs.length) activateTab(tabs[0]);
  setLanguage(requestedLanguage || safeStorage.get('lunav-language') || 'th');
  applyMotion();
  sizeSky();
  updateTabMarker();
  document.fonts.ready.then(() => { updateTabMarker(); requestRender(); });
  window.addEventListener('lunav:introcomplete', () => { lastFrame = 0; requestRender(); });
})();
