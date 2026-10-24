/* Copyright (C) 2026 Wachirawich Kripindakul. SPDX-License-Identifier: AGPL-3.0-or-later. See LICENSE. */
(() => {
  'use strict';
  const root = document.documentElement;
  const screen = document.querySelector('#luna-intro');
  const target = document.querySelector('.site-header .brand');
  const replay = document.querySelector('#intro-replay');
  if (!screen || !target || !Element.prototype.animate) return;
  const lockup = screen.querySelector('.intro-lockup');
  const moon = screen.querySelector('.intro-moon');
  const word = screen.querySelector('.intro-word');
  const retired = screen.querySelector('.intro-retired');
  const path = screen.querySelector('.intro-crossout path');
  const pen = screen.querySelector('.intro-pen');
  const curtain = screen.querySelector('.intro-curtain');
  const protectedNodes = [...document.querySelectorAll('.site-header, main, .site-footer, .skip-link')];
  const motion = matchMedia('(prefers-reduced-motion: reduce)');
  const animations = new Set();
  let controller = null, failSafe = null, previousFocus = null, savedInert = [], keyboardInteraction = false;
  const reduced = () => motion.matches || root.classList.contains('motion-reduced');

  function animate(element, keyframes, options) {
    const animation = element.animate(keyframes, { fill: 'forwards', easing: 'cubic-bezier(.22,1,.36,1)', ...options });
    animations.add(animation);
    return animation.finished;
  }
  function pause(ms, signal) {
    return new Promise((resolve, reject) => {
      if (signal.aborted) { reject(new DOMException('Intro stopped', 'AbortError')); return; }
      const abort = () => { clearTimeout(timer); reject(new DOMException('Intro stopped', 'AbortError')); };
      const timer = setTimeout(() => { signal.removeEventListener('abort', abort); resolve(); }, ms);
      signal.addEventListener('abort', abort, { once: true });
    });
  }
  function finish() {
    if (!controller) return;
    controller.abort(); controller = null;
    clearTimeout(failSafe);
    animations.forEach(animation => animation.cancel()); animations.clear();
    const returnFocus = screen.contains(document.activeElement);
    if (returnFocus && !keyboardInteraction) document.activeElement.blur();
    screen.hidden = true; screen.dataset.stage = 'complete';
    root.classList.remove('intro-playing');
    savedInert.forEach(([node, wasInert]) => { node.inert = wasInert; }); savedInert = [];
    if (returnFocus && keyboardInteraction) {
      const destination = previousFocus && previousFocus !== document.body && previousFocus.isConnected ? previousFocus : target;
      destination.focus({ preventScroll: true });
    }
    window.dispatchEvent(new Event('lunav:introcomplete'));
  }
  function reset() {
    [lockup, moon, word, retired, path, pen, curtain].forEach(el => el.removeAttribute('style'));
    lockup.classList.remove('is-inline');
  }
  async function start(fromKeyboard = false) {
    if (controller || reduced() || document.hidden) return;
    controller = new AbortController();
    const signal = controller.signal;
    previousFocus = document.activeElement;
    keyboardInteraction = fromKeyboard;
    try {
      reset(); screen.hidden = false; screen.dataset.stage = 'wordmark';
      savedInert = protectedNodes.map(node => [node, node.inert]);
      savedInert.forEach(([node]) => { node.inert = true; });
      root.classList.add('intro-playing');
      failSafe = setTimeout(() => finish(), 8000);
      screen.tabIndex = -1;
      screen.focus({ preventScroll: true });
      await Promise.race([document.fonts.ready, pause(450, signal)]);
      if (signal.aborted) return;
      await animate(lockup, [{ opacity: 0, translate: '0 10px', scale: .97 }, { opacity: 1, translate: '0 0', scale: 1 }], { duration: 380 });
      await pause(430, signal);
      screen.dataset.stage = 'strike';
      // The nib and ink share the same arc-length timeline, including each wave.
      // Screen-space SVG coordinates keep the tip aligned at every viewport size.
      const inkLength = path.getTotalLength();
      const inkMatrix = path.getScreenCTM();
      const writingArea = retired.getBoundingClientRect();
      const pointAt = fraction => {
        const point = path.getPointAtLength(inkLength * fraction);
        const screenPoint = new DOMPoint(point.x, point.y).matrixTransform(inkMatrix);
        return { x: screenPoint.x - writingArea.left, y: screenPoint.y - writingArea.top };
      };
      const at = (point, dx = 0, dy = 0) => `translate(${point.x + dx}px, ${point.y + dy}px)`;
      const firstPoint = pointAt(0), lastPoint = pointAt(1);
      await animate(pen, [{ opacity: 0, transform: at(firstPoint, 12, -18) }, { opacity: 1, transform: at(firstPoint) }], { duration: 180 });
      const tipFrames = Array.from({ length: 101 }, (_, index) => {
        const fraction = index / 100;
        return { offset: fraction, opacity: 1, transform: at(pointAt(fraction)) };
      });
      await Promise.all([
        animate(path, [{ strokeDashoffset: 1 }, { strokeDashoffset: 0 }], { duration: 780, easing: 'linear' }),
        animate(pen, tipFrames, { duration: 780, easing: 'linear' })
      ]);
      await animate(pen, [{ opacity: 1, transform: at(lastPoint) }, { opacity: 0, transform: at(lastPoint, 14, -22) }], { duration: 180 });
      await pause(350, signal);
      screen.dataset.stage = 'erase';
      await animate(retired, [{ width: `${retired.getBoundingClientRect().width}px`, opacity: 1, filter: 'blur(0px)' }, { width: '0px', opacity: 0, filter: 'blur(5px)' }], { duration: 440 });
      retired.style.width = '0px'; retired.style.opacity = '0';
      screen.dataset.stage = 'align';
      const beforeMoon = moon.getBoundingClientRect();
      const beforeWord = word.getBoundingClientRect();
      const style = getComputedStyle(target);
      const targetMoon = target.querySelector('.brand-icon').getBoundingClientRect();
      const ratio = Math.min(3, (innerWidth - 44) / target.getBoundingClientRect().width);
      lockup.style.fontSize = `${parseFloat(style.fontSize) * ratio}px`;
      lockup.style.gap = `${parseFloat(style.columnGap) * ratio}px`;
      lockup.style.letterSpacing = `${parseFloat(style.letterSpacing) * ratio}px`;
      moon.style.width = `${targetMoon.width * ratio}px`; moon.style.height = `${targetMoon.height * ratio}px`;
      lockup.classList.add('is-inline');
      const afterMoon = moon.getBoundingClientRect();
      const afterWord = word.getBoundingClientRect();
      await Promise.all([
        animate(moon, [{ transformOrigin: '0 0', transform: `translate(${beforeMoon.left - afterMoon.left}px, ${beforeMoon.top - afterMoon.top}px) scale(${beforeMoon.width / afterMoon.width})` }, { transformOrigin: '0 0', transform: 'none' }], { duration: 480 }),
        animate(word, [{ transformOrigin: '0 0', transform: `translate(${beforeWord.left - afterWord.left}px, ${beforeWord.top - afterWord.top}px) scale(${beforeWord.height / afterWord.height})` }, { transformOrigin: '0 0', transform: 'none' }], { duration: 480 })
      ]);
      await pause(100, signal);
      if (signal.aborted) return;
      screen.dataset.stage = 'dock';
      const from = lockup.getBoundingClientRect();
      const destination = target.getBoundingClientRect();
      lockup.style.left = `${from.left}px`; lockup.style.top = `${from.top}px`;
      lockup.style.transform = 'none'; lockup.style.transformOrigin = '0 0';
      await Promise.all([
        animate(lockup, [{ transform: 'translate(0,0) scale(1)' }, { transform: `translate(${destination.left - from.left}px, ${destination.top - from.top}px) scale(${destination.width / from.width})` }], { duration: 900, easing: 'cubic-bezier(.65,0,.2,1)' }),
        animate(curtain, [{ opacity: 1 }, { opacity: 0 }], { duration: 800, delay: 100, easing: 'ease-in-out' })
      ]);
      finish();
    } catch (error) {
      if (!signal.aborted) finish();
    }
  }
  document.addEventListener('keydown', event => {
    if (!controller) return;
    keyboardInteraction = true;
    if (event.key === 'Tab') { event.preventDefault(); screen.focus({ preventScroll: true }); }
    if (event.key === 'Escape') { event.preventDefault(); finish(); }
  });
  document.addEventListener('visibilitychange', () => { if (document.hidden) finish(); });
  window.addEventListener('resize', () => { if (controller) finish(); }, { passive: true });
  motion.addEventListener('change', () => { if (reduced()) finish(); });
  window.addEventListener('lunav:motionchange', () => { if (reduced()) finish(); });
  replay?.addEventListener('click', async event => {
    if (controller || reduced()) return;
    window.scrollTo({ top: 0, behavior: 'instant' });
    await new Promise(resolve => requestAnimationFrame(resolve));
    start(event.detail === 0);
  });
  if (replay) replay.hidden = reduced();
  window.addEventListener('lunav:motionchange', () => { if (replay) replay.hidden = reduced(); });
  motion.addEventListener('change', () => { if (replay) replay.hidden = reduced(); });
  const restoringHistory = performance.getEntriesByType('navigation')[0]?.type === 'back_forward';
  if (!restoringHistory && (!location.hash || location.hash === '#overview') && window.scrollY < 10) start();
})();
