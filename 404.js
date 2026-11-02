/* Copyright (C) 2026 Wachirawich Kripindakul. SPDX-License-Identifier: AGPL-3.0-or-later. See LICENSE. */
(() => {
  'use strict';
  const root = document.documentElement;
  const code = document.querySelector('.lost-label-code');
  const message = document.querySelector('.lost-label-message');
  if (!code || !message) return;
  const systemMotion = matchMedia('(prefers-reduced-motion: reduce)');
  const animations = [];
  const copies = [];
  const introEvents = new AbortController();
  let finished = false;
  let watchdog;

  function finish() {
    if (finished) return;
    finished = true;
    root.classList.remove('lost-intro-pending', 'lost-intro-running');
    animations.forEach(animation => animation.cancel());
    copies.forEach(copy => copy.remove());
    introEvents.abort();
    clearTimeout(watchdog);
  }
  function updateMotion() {
    let manual = false;
    try { manual = localStorage.getItem('lunav-reduce-motion') === 'true'; } catch { /* Storage can be unavailable. */ }
    const reduced = systemMotion.matches || manual;
    root.classList.toggle('lost-motion-reduced', reduced);
    if (reduced) finish();
  }
  function updateVisibility() {
    root.classList.toggle('lost-page-hidden', document.hidden);
    if (document.hidden) finish();
  }
  systemMotion.addEventListener('change', updateMotion);
  window.addEventListener('storage', event => { if (event.key === 'lunav-reduce-motion') updateMotion(); });
  document.addEventListener('visibilitychange', updateVisibility);
  updateMotion();
  updateVisibility();
  if (finished || !root.classList.contains('lost-intro-pending')) { finish(); return; }

  // Recovery links remain usable immediately, even during the entrance.
  const signal = introEvents.signal;
  window.addEventListener('pointerdown', finish, { capture: true, signal });
  window.addEventListener('keydown', finish, { capture: true, signal });
  window.addEventListener('wheel', finish, { passive: true, signal });
  window.addEventListener('resize', finish, { signal });
  window.addEventListener('pagehide', finish, { signal });
  window.addEventListener('beforeprint', finish, { signal });
  window.addEventListener('lunav:languagechange', finish, { signal });
  watchdog = setTimeout(finish, 4500);

  function makeCopy(target, className) {
    const style = getComputedStyle(target);
    const rect = target.getBoundingClientRect();
    const copy = document.createElement('span');
    copy.className = `lost-intro-glyph ${className}`;
    copy.setAttribute('aria-hidden', 'true');
    copy.textContent = target.textContent;
    for (const property of ['fontFamily', 'fontSize', 'fontWeight', 'fontStyle', 'letterSpacing', 'lineHeight', 'color']) copy.style[property] = style[property];
    Object.assign(copy.style, { left: `${rect.left}px`, top: `${rect.top}px`, width: `${rect.width}px`, height: `${rect.height}px` });
    copies.push(copy);
    return { copy, rect, style, fontSize: parseFloat(style.fontSize), color: style.color };
  }

  async function enter() {
    try {
      await document.fonts.ready;
      if (finished || !root.classList.contains('lost-intro-pending')) return;
      const items = [makeCopy(code, 'lost-intro-code'), makeCopy(message, 'lost-intro-message')];
      const width = document.documentElement.clientWidth;
      const height = window.innerHeight;
      const headerHeight = document.querySelector('.site-header').getBoundingClientRect().bottom;
      const desiredSizes = [Math.min(240, width * .38, (height - headerHeight) * .34), Math.min(38, width * .075)];
      const scales = items.map((item, index) => Math.max(1, Math.min(desiredSizes[index] / item.fontSize, (width - 48) / item.rect.width)));
      const gap = 14;
      const totalHeight = items.reduce((sum, item, index) => sum + item.rect.height * scales[index], gap);
      let top = headerHeight + Math.max(20, (height - headerHeight - totalHeight) / 2);

      items.forEach((item, index) => {
        const { copy, rect, style, color, fontSize } = item;
        const scale = scales[index];
        // Typeset at the largest displayed size. WebKit can magnify a small
        // composited text layer as a bitmap when a transform scales it up.
        copy.style.fontSize = `${fontSize * scale}px`;
        copy.style.lineHeight = `${parseFloat(style.lineHeight) * scale}px`;
        if (style.letterSpacing !== 'normal') copy.style.letterSpacing = `${parseFloat(style.letterSpacing) * scale}px`;
        copy.style.width = `${rect.width * scale}px`;
        copy.style.height = `${rect.height * scale}px`;
        const left = (width - rect.width * scale) / 2;
        const from = `translate(${left - rect.left}px, ${top - rect.top}px) scale(1)`;
        const to = `translate(0px, 0px) scale(${1 / scale})`;
        const startColor = index === 0 ? '#f2f0e9' : color;
        copy.style.transform = from;
        document.body.append(copy);
        animations.push(copy.animate([
          { transform: from, color: startColor, offset: 0 },
          { transform: from, color: startColor, offset: .3, easing: 'cubic-bezier(.22,1,.36,1)' },
          { transform: to, color, offset: 1 }
        ], { duration: 2200, easing: 'linear', fill: 'both' }));
        top += rect.height * scale + gap;
      });

      root.classList.replace('lost-intro-pending', 'lost-intro-running');
      document.querySelectorAll('.lost-copy > :not(.lost-label), .lost-scene, .lost-footer').forEach(el => {
        animations.push(el.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 800, delay: 600, easing: 'ease-out', fill: 'both' }));
      });
      const divider = document.querySelector('.lost-label-divider');
      animations.push(divider.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 550, delay: 1450, fill: 'both' }));
      await Promise.all(animations.slice(0, 2).map(animation => animation.finished));
    } catch { /* Cancellation and unavailable animation APIs fall back to the static page. */ }
    finally { finish(); }
  }
  enter();
})();
