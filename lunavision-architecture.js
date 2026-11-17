/* Copyright (C) 2026 Wachirawich Kripindakul. SPDX-License-Identifier: AGPL-3.0-or-later. See LICENSE. */
(() => {
  'use strict';

  const player = document.querySelector('[data-flow-player]');
  const nodes = [...player.querySelectorAll('[data-flow-node]')];
  const captions = [...player.querySelectorAll('[data-flow-caption]')];
  const overview = player.querySelector('[data-flow-overview]');
  const replay = player.querySelector('[data-flow-replay]');
  const pause = player.querySelector('[data-flow-pause]');
  const playLabel = replay.querySelector('[data-flow-play-label]');
  const replayLabel = replay.querySelector('[data-flow-replay-label]');
  const pauseLabel = pause.querySelector('[data-flow-pause-label]');
  const resumeLabel = pause.querySelector('[data-flow-resume-label]');
  const motion = matchMedia('(prefers-reduced-motion: reduce)');
  const duration = [2600, 2800, 3600, 2600];

  let current = -1;
  let state = 'ready';
  let remaining = 0;
  let deadline = 0;
  let timer;
  let observer;
  let visible = false;
  const destination = document.getElementById(location.hash.slice(1));
  let autoplay = (!destination || destination.id === 'main' || Boolean(destination.closest('#journey')))
    && performance.getEntriesByType('navigation')[0]?.type !== 'back_forward';

  function reducedMotion() {
    try {
      return motion.matches || localStorage.getItem('lunav-reduce-motion') === 'true';
    } catch {
      return motion.matches;
    }
  }

  function showStep(index) {
    current = index;
    player.dataset.flowStep = String(index);
    overview.toggleAttribute('data-active', index === -1);
    nodes.forEach((node, i) => {
      node.toggleAttribute('data-reached', i <= index);
      if (i === index) node.setAttribute('aria-current', 'step');
      else node.removeAttribute('aria-current');
      captions[i].toggleAttribute('data-active', i === index);
    });
  }

  function setState(next) {
    state = next;
    player.dataset.playback = next;
    const canPause = next === 'playing' || next === 'paused';
    pause.setAttribute('aria-disabled', String(!canPause));
    pauseLabel.hidden = next === 'paused';
    resumeLabel.hidden = next !== 'paused';
  }

  function schedule(delay) {
    deadline = performance.now() + delay;
    timer = setTimeout(() => {
      if (current === captions.length - 1) {
        setState('complete');
        return;
      }
      showStep(current + 1);
      schedule(duration[current]);
    }, delay);
  }

  function start() {
    clearTimeout(timer);
    observer?.disconnect();
    autoplay = false;
    playLabel.hidden = true;
    replayLabel.hidden = false;
    showStep(0);
    setState('playing');
    schedule(duration[0]);
  }

  function pausePlayback() {
    clearTimeout(timer);
    remaining = Math.max(0, deadline - performance.now());
    setState('paused');
  }

  function maybeAutoplay() {
    if (autoplay && visible && !document.hidden) start();
  }

  function updateMotion() {
    const reduced = reducedMotion();
    player.toggleAttribute('data-reduced-motion', reduced);
    if (!reduced) return;
    autoplay = false;
    observer?.disconnect();
    if (state === 'playing' || state === 'paused') {
      clearTimeout(timer);
      showStep(-1);
      setState('ready');
    }
  }

  replay.addEventListener('click', start);
  pause.addEventListener('click', () => {
    if (state === 'playing') pausePlayback();
    else if (state === 'paused') {
      setState('playing');
      schedule(remaining);
    }
  });

  motion.addEventListener('change', updateMotion);
  addEventListener('lunav:motionchange', updateMotion);
  addEventListener('storage', event => {
    if (event.key === 'lunav-reduce-motion' || event.key === null) updateMotion();
  });
  document.addEventListener('visibilitychange', () => {
    if (document.hidden && state === 'playing') pausePlayback();
    else maybeAutoplay();
  });

  setState('ready');
  updateMotion();
  player.querySelector('[data-flow-controls]').hidden = false;
  pause.hidden = false;
  if (autoplay) {
    observer = new IntersectionObserver(([entry]) => {
      visible = entry.intersectionRatio >= .45;
      maybeAutoplay();
    }, { threshold: .45 });
    observer.observe(player.querySelector('.flow-scene'));
  }
})();
