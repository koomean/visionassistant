/* Copyright (C) 2026 Wachirawich Kripindakul. SPDX-License-Identifier: AGPL-3.0-or-later. */
import { assessCompatibility, detectDevice, minimumIOS } from './device-compatibility.js?v=luna-20261112-check';

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

  const check = document.getElementById('device-check');
  const choice = document.getElementById('device-check-choice');
  const picker = document.getElementById('device-check-model');
  const catalogDepths = new Map(models.map(({ element, depth }) => [element.dataset.model, depth]));
  const catalogEvidence = new Map(models.map(({ element }) => [element.dataset.model, element.querySelector('.model-evidence')]));
  let device;

  function localized(th, en) {
    return document.documentElement.lang === 'en' ? en : th;
  }

  function setCheckText(key, text) {
    const node = document.getElementById(`device-check-${key}`);
    if (node.textContent !== text) node.textContent = text;
    node.hidden = !text;
  }

  function updateDeviceCheck() {
    const model = picker.value;
    const result = assessCompatibility(device, catalogDepths, model);
    const kind = device.platform;
    const possible = device.candidates.length;
    const ios = `iOS ${minimumIOS}`;
    const detectedOS = device.osMajor ? `iOS ${device.osMajor}` : '';
    check.dataset.compatibility = result.status;

    const name = result.model || ({ iphone: 'iPhone', mac: 'Mac', ipad: 'iPad', android: 'Android' })[kind]
      || localized('อุปกรณ์นี้', 'This device');
    setCheckText('name', name);
    const statuses = {
      supported: localized('รุ่นและ iOS รองรับ LunaV', 'Your model and iOS version meet the requirements'),
      likely: localized('น่าจะใช้ LunaV ได้', 'Likely compatible'),
      update: localized(`ต้องอัปเดตเป็น ${ios} ขึ้นไป`, `Update to ${ios} or later`),
      'check-os': localized('ตรวจเวอร์ชัน iOS', 'Check your iOS version'),
      'check-model': localized('ต้องยืนยันรุ่นก่อน', 'Confirm your model'),
      unsupported: localized('อุปกรณ์นี้ไม่รองรับ', 'This device is not supported'),
    };
    setCheckText('status', statuses[result.status]);

    let detail;
    if (kind === 'apple-mobile' && !model) {
      detail = localized('ตอนนี้เบราว์เซอร์เปิดเว็บแบบเดสก์ท็อป ถ้าใช้ iPhone ให้เลือกรุ่นหรือเปิดเว็บแบบมือถือ', 'You’re viewing the desktop site. On iPhone, select your model below or switch to the mobile site.');
    } else if (kind !== 'iphone' && kind !== 'apple-mobile') {
      detail = kind === 'mac'
        ? localized('LunaV เป็นแอป iPhone ดูข้อกำหนดสำหรับสร้างแอปบน Mac ได้ด้านล่าง', 'LunaV runs on iPhone. See the Mac build requirements below.')
        : localized(`LunaV ใช้ได้เฉพาะ iPhone ที่ใช้ ${ios} ขึ้นไป`, `LunaV runs only on iPhones with ${ios} or later.`);
    } else {
      const modelNote = model
        ? ''
        : possible > 1
          ? localized(`ขนาดหน้าจอตรงกับ iPhone ${possible} รุ่น เลือกรุ่นของคุณด้านล่าง`, `${possible} iPhone models match this screen size. Select yours below.`)
          : possible === 1
            ? localized('คาดจากขนาดหน้าจอ เช็กชื่อรุ่นเพื่อยืนยัน', 'Suggested from your screen size. Check the model name to confirm.')
            : localized('เบราว์เซอร์ระบุรุ่นไม่ได้ เลือกจากรายการด้านล่าง', 'Your browser couldn’t identify the model. Choose it below.');
      const osNote = result.status === 'unsupported'
        ? localized(`รุ่นนี้อัปเดตเป็น ${ios} ไม่ได้`, `This model can’t update to ${ios}.`)
        : detectedOS
          ? localized(`ตรวจพบ ${detectedOS}`, `Detected ${detectedOS}.`)
          : localized(`ตรวจที่ การตั้งค่า → ทั่วไป → เกี่ยวกับ (ต้องใช้ ${ios} ขึ้นไป)`, `Check in Settings → General → About. LunaV needs ${ios} or later.`);
      detail = [modelNote, osNote].filter(Boolean).join(localized(' · ', ' '));
    }
    setCheckText('description', detail);
    setCheckText('matches', !model && possible > 1 ? device.candidates.join(' · ') : '');
    setCheckText('depth', result.depth === 'lidar'
      ? localized('วัดระยะด้วย LiDAR ด้านหลัง', 'Measures distance with rear LiDAR')
      : result.depth === 'da3'
        ? localized('ใช้ Depth Anything 3 ประมาณระยะเมื่อมีข้อมูลเลนส์', 'Depth Anything 3 estimates distance when lens data is available')
        : '');
    setCheckText('evidence', model ? (catalogEvidence.get(model)?.textContent || '') : '');
  }

  function updatePickerLabels() {
    picker.options[0].text = localized('เลือกรุ่น iPhone', 'Choose an iPhone model');
    for (const group of picker.querySelectorAll('optgroup')) {
      group.label = group.dataset.suggested === 'true'
        ? localized('รุ่นที่ตรงกับขนาดจอ', 'Screen matches')
        : localized(device.candidates.length ? 'iPhone รุ่นอื่น' : 'iPhone ทุกรุ่น', device.candidates.length ? 'Other iPhone models' : 'All iPhone models');
    }
  }

  function readDevice() {
    const next = detectDevice({
      userAgent: navigator.userAgent,
      platform: navigator.platform,
      maxTouchPoints: navigator.maxTouchPoints,
      width: screen.width,
      height: screen.height,
      pixelRatio: window.devicePixelRatio,
    });
    if (device && next.platform === device.platform && next.osMajor === device.osMajor
      && next.candidates.join() === device.candidates.join()) return;
    device = next;
    const previous = picker.value;
    picker.replaceChildren(new Option('', ''));
    const candidates = new Set(device.candidates);
    for (const suggested of [true, false]) {
      const group = document.createElement('optgroup');
      group.dataset.suggested = String(suggested);
      for (const model of catalogDepths.keys()) {
        if (candidates.has(model) === suggested) group.append(new Option(model, model));
      }
      if (group.children.length) picker.append(group);
    }
    if (catalogDepths.has(previous)) picker.value = previous;
    choice.hidden = !['iphone', 'apple-mobile'].includes(device.platform);
    updatePickerLabels();
    updateDeviceCheck();
    check.hidden = false;
  }

  picker.addEventListener('change', updateDeviceCheck);
  window.addEventListener('lunav:languagechange', () => {
    updatePickerLabels();
    updateDeviceCheck();
  });
  window.addEventListener('resize', readDevice, { passive: true });
  readDevice();

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
