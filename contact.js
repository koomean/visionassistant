/* Copyright (C) 2026 Wachirawich Kripindakul. SPDX-License-Identifier: AGPL-3.0-or-later. See LICENSE. */
(() => {
  'use strict';
  const root = document.documentElement;
  if (!document.body.classList.contains('contact-page')) return;
  const canvas = document.querySelector('#starfield');
  const context = canvas?.getContext('2d');
  const scene = document.querySelector('.contact-lunar-scene');
  const section = document.querySelector('section.contact');
  const header = document.querySelector('.site-header');
  const systemMotion = matchMedia('(prefers-reduced-motion: reduce)');
  const finePointer = matchMedia('(hover: hover) and (pointer: fine)');
  let reduced = false;
  let width = innerWidth, height = innerHeight, stars = [];
  let frame = 0, lastFrame = 0, entranceTimer = 0;
  let visualScroll = Math.max(0, scrollY);
  let pointerX = 0, pointerY = 0, visualX = 0, visualY = 0;
  let sceneCentre = 0;
  let revealObserver;

  function seeded(seed) {
    return () => { seed = (seed * 16807) % 2147483647; return (seed - 1) / 2147483646; };
  }
  function requestRender() {
    if (!frame && !document.hidden) frame = requestAnimationFrame(render);
  }
  function measureScene() {
    if (scene) {
      const rect = scene.getBoundingClientRect();
      sceneCentre = rect.top + scrollY + rect.height / 2;
    }
  }
  function sizeSky() {
    width = innerWidth;
    height = innerHeight;
    if (context) {
      const dpr = Math.min(devicePixelRatio || 1, 2);
      canvas.width = Math.round(width * dpr);
      canvas.height = Math.round(height * dpr);
      context.setTransform(dpr, 0, 0, dpr, 0, 0);
      const random = seeded(17072026);
      stars = Array.from({ length: Math.min(150, Math.round(width * height / 7500)) }, () => ({
        x: random() * width, y: random() * height, radius: .45 + random() * .9,
        alpha: .2 + random() * .55, depth: .045 + random() * .075
      }));
    }
    measureScene();
    requestRender();
  }
  function drawSky() {
    if (!context) return;
    context.clearRect(0, 0, width, height);
    for (const star of stars) {
      const x = ((star.x + visualX * star.depth * 10) % width + width) % width;
      const offset = reduced ? 0 : visualScroll * star.depth - visualY * star.depth * 10;
      const y = ((star.y - offset) % height + height) % height;
      context.beginPath();
      context.arc(x, y, star.radius, 0, Math.PI * 2);
      context.fillStyle = `rgba(197,211,239,${star.alpha})`;
      context.fill();
      if (star.radius > 1.2) {
        context.strokeStyle = `rgba(197,211,239,${star.alpha * .45})`;
        context.lineWidth = .5;
        context.beginPath();
        context.moveTo(x - 3, y); context.lineTo(x + 3, y);
        context.moveTo(x, y - 3); context.lineTo(x, y + 3);
        context.stroke();
      }
    }
  }
  function render(timestamp) {
    frame = 0;
    if (document.hidden) return;
    const scroll = Math.max(0, scrollY);
    const delta = lastFrame ? Math.min(64, Math.max(1, timestamp - lastFrame)) : 16.67;
    lastFrame = timestamp;
    const settle = 1 - Math.exp(-delta / 90);
    if (reduced || Math.abs(scroll - visualScroll) > height * 2) visualScroll = scroll;
    else visualScroll += (scroll - visualScroll) * settle;
    if (Math.abs(scroll - visualScroll) < .15) visualScroll = scroll;
    visualX = reduced ? 0 : visualX + (pointerX - visualX) * settle;
    visualY = reduced ? 0 : visualY + (pointerY - visualY) * settle;
    if (Math.abs(pointerX - visualX) < .002) visualX = pointerX;
    if (Math.abs(pointerY - visualY) < .002) visualY = pointerY;
    const lift = reduced ? 0 : Math.max(-12, Math.min(14, (height / 2 - sceneCentre + visualScroll) * .035));
    root.style.setProperty('--contact-moon-x', `${(visualX * 5).toFixed(2)}px`);
    root.style.setProperty('--contact-moon-y', `${(lift + visualY * 4).toFixed(2)}px`);
    root.style.setProperty('--contact-moon-turn', `${(reduced ? 0 : lift * .08 + visualX * .6).toFixed(2)}deg`);
    root.style.setProperty('--contact-constellation-y', `${(reduced ? 0 : -lift * .35).toFixed(2)}px`);
    header?.classList.toggle('scrolled', scroll > 20);
    drawSky();
    if (!reduced && (visualScroll !== scroll || visualX !== pointerX || visualY !== pointerY)) requestRender();
  }
  function revealContact(animate = true) {
    if (!section) return;
    const waiting = section.classList.contains('contact-awaiting');
    section.classList.remove('contact-awaiting');
    if (waiting && animate && !reduced) section.classList.add('contact-revealed');
    revealObserver?.disconnect();
  }
  function finishEntrance() {
    clearTimeout(entranceTimer);
    root.classList.remove('contact-entry-pending', 'contact-entering');
  }
  function applyMotion() {
    let manual = false;
    try { manual = localStorage.getItem('lunav-reduce-motion') === 'true'; } catch { /* Motion also follows system preferences. */ }
    reduced = manual || systemMotion.matches;
    root.classList.toggle('contact-motion-enabled', !reduced);
    root.classList.toggle('contact-motion-reduced', reduced);
    if (reduced) {
      pointerX = pointerY = visualX = visualY = 0;
      finishEntrance();
      revealContact(false);
    }
    lastFrame = 0;
    requestRender();
  }

  systemMotion.addEventListener('change', applyMotion);
  window.addEventListener('storage', event => { if (event.key === 'lunav-reduce-motion') applyMotion(); });
  window.addEventListener('lunav:motionchange', applyMotion);
  window.addEventListener('lunav:languagechange', () => { measureScene(); requestRender(); });
  window.addEventListener('scroll', requestRender, { passive: true });
  window.addEventListener('resize', sizeSky, { passive: true });
  window.addEventListener('pointermove', event => {
    if (reduced || !finePointer.matches || event.pointerType !== 'mouse') return;
    pointerX = (event.clientX / width - .5) * 2;
    pointerY = (event.clientY / height - .5) * 2;
    requestRender();
  }, { passive: true });
  document.addEventListener('pointerleave', () => { pointerX = pointerY = 0; requestRender(); });
  finePointer.addEventListener('change', () => { pointerX = pointerY = 0; requestRender(); });
  document.addEventListener('visibilitychange', () => {
    lastFrame = 0;
    if (document.hidden) {
      cancelAnimationFrame(frame);
      frame = 0;
      finishEntrance();
      revealContact(false);
    } else requestRender();
  });
  window.addEventListener('pagehide', () => { cancelAnimationFrame(frame); frame = 0; finishEntrance(); });
  window.addEventListener('pageshow', () => { lastFrame = 0; requestRender(); });
  section?.addEventListener('focusin', () => { revealContact(false); finishEntrance(); });
  window.addEventListener('keydown', finishEntrance, { once: true, capture: true });
  window.addEventListener('pointerdown', finishEntrance, { once: true, capture: true });
  window.addEventListener('beforeprint', () => { finishEntrance(); revealContact(false); });

  applyMotion();
  if (!reduced && !document.hidden && root.classList.contains('contact-entry-pending')) {
    root.classList.replace('contact-entry-pending', 'contact-entering');
    entranceTimer = setTimeout(finishEntrance, 1000);
    if (section && 'IntersectionObserver' in window && section.getBoundingClientRect().top >= innerHeight) {
      section.classList.add('contact-awaiting');
      revealObserver = new IntersectionObserver(entries => {
        if (entries.some(entry => entry.isIntersecting)) revealContact();
      }, { threshold: .01, rootMargin: '0px 0px 24px 0px' });
      revealObserver.observe(section);
    }
  } else finishEntrance();
  sizeSky();
  if ('ResizeObserver' in window) new ResizeObserver(() => { measureScene(); requestRender(); }).observe(document.body);
  document.fonts?.ready.then(() => { measureScene(); requestRender(); });
})();
