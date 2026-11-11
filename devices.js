/* Copyright (C) 2026 Wachirawich Kripindakul. SPDX-License-Identifier: AGPL-3.0-or-later. */
(() => {
  'use strict';
  const tools = document.getElementById('catalog-tools');
  const input = document.getElementById('model-search');
  const result = document.getElementById('catalog-result');
  const catalog = document.getElementById('iphone-catalog');
  const legacy = document.getElementById('legacy-models');
  const filters = [...tools.querySelectorAll('[data-filter]')];
  const groups = [...catalog.querySelectorAll('.model-family, .legacy-models')];
  const normalize = text => text.toLowerCase().replace(/[^a-z0-9\u0e00-\u0e7f]/g, '');
  const models = [...catalog.querySelectorAll('[data-model]')].map(element => ({
    element,
    name: normalize(element.dataset.model),
    alias: normalize(element.dataset.alias || ''),
    depth: element.dataset.depth,
  }));
  let selected = 'all';
  let openedForFilter = false;

  function update() {
    const query = normalize(input.value);
    const showLegacy = selected === 'legacy' || Boolean(query);
    let count = 0;
    for (const model of models) {
      const matches = (selected === 'all' || model.depth === selected)
        && (model.name.includes(query) || model.alias.includes(query));
      model.element.hidden = !matches;
      count += Number(matches);
    }
    for (const group of groups) group.hidden = !group.querySelector('[data-model]:not([hidden])');

    if (showLegacy && !legacy.hidden && !legacy.open) {
      legacy.open = true;
      openedForFilter = true;
    } else if (!showLegacy && openedForFilter) {
      legacy.open = false;
      openedForFilter = false;
    }
    const english = document.documentElement.lang === 'en';
    const formatted = count.toLocaleString(english ? 'en' : 'th');
    const message = english
      ? (count ? `${formatted} ${count === 1 ? 'model' : 'models'}` : 'No matching iPhone models.')
      : (count ? `${formatted} รุ่น` : 'ไม่พบ iPhone ที่ตรงกับการค้นหา');
    if (result.textContent !== message) result.textContent = message;
  }

  input.addEventListener('input', update);
  for (const button of filters) button.addEventListener('click', () => {
    selected = button.dataset.filter;
    for (const filter of filters) filter.setAttribute('aria-pressed', String(filter === button));
    update();
  });
  window.addEventListener('lunav:languagechange', update);
  tools.hidden = false;
  result.hidden = false;
  update();
})();
