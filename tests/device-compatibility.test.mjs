// Copyright (C) 2026 Wachirawich Kripindakul. SPDX-License-Identifier: AGPL-3.0-or-later.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { detectDevice, assessCompatibility, displayModels } from '../device-compatibility.js';

const catalog = new Map([...readFileSync(new URL('../devices.html', import.meta.url), 'utf8')
  .matchAll(/data-model="([^"]+)" data-depth="([^"]+)"/g)].map(([, model, depth]) => [model, depth]));
const safari = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.2 Mobile/15E148 Safari/604.1';
const phone = overrides => detectDevice({ userAgent: safari, width: 393, height: 852, pixelRatio: 3, ...overrides });

test('identifies Mac, desktop-mode iPad, native iPad and Android as non-iPhone', () => {
  const mac = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Version/27.2 Safari/605.1.15';
  for (const [ua, platform, maxTouchPoints, expected] of [
    [mac, 'MacIntel', 0, 'mac'], [mac, 'MacIntel', 5, 'ipad'], ['Mozilla/5.0 (iPad; CPU OS 27_2)', 'iPad', 5, 'ipad'],
    ['Mozilla/5.0 (Linux; Android 16; Pixel 9)', 'Linux', 5, 'android'],
    ['Mozilla/5.0 (Windows NT 10.0)', 'Win32', 0, 'other'],
  ]) {
    const device = phone({ userAgent: ua, platform, maxTouchPoints, ...(expected === 'ipad' ? { width: 820, height: 1180, pixelRatio: 2 } : {}) });
    assert.equal(device.platform, expected);
    assert.equal(assessCompatibility(device, catalog).status, 'unsupported');
    assert.deepEqual(device.candidates, []);
  }
});

test('desktop-mode Apple phone screens get a confirmation path without claiming an iPad or Mac', () => {
  const device = phone({ userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Version/27.2 Safari/605.1.15', platform: 'MacIntel', maxTouchPoints: 5 });
  assert.equal(device.platform, 'apple-mobile');
  assert.equal(assessCompatibility(device, catalog).status, 'check-model');
  assert.equal(assessCompatibility(device, catalog, 'iPhone 14 Pro').status, 'check-os');
});

test('retains every 14 Pro screen match and never infers a depth source across models', () => {
  const device = phone();
  assert.deepEqual(device.candidates, ['iPhone 14 Pro', 'iPhone 15', 'iPhone 15 Pro', 'iPhone 16']);
  assert.deepEqual(phone({ width: 852, height: 393 }).candidates, device.candidates);
  const automatic = assessCompatibility(device, catalog);
  assert.equal(automatic.status, 'likely');
  assert.equal(automatic.depth, null);
  const selected = assessCompatibility(device, catalog, 'iPhone 14 Pro');
  assert.equal(selected.status, 'supported');
  assert.equal(selected.depth, 'lidar');
  assert.equal(assessCompatibility(device, catalog, 'iPhone 16').depth, 'da3');
});

test('suggests single screen matches without treating the model as confirmed', () => {
  const device = phone({ width: 420, height: 912 });
  assert.deepEqual(device.candidates, ['iPhone Air']);
  assert.equal(assessCompatibility(device, catalog).status, 'likely');
  assert.equal(assessCompatibility(device, catalog).depth, 'da3');
});

test('uses Safari version instead of frozen iOS token; avoids using third-party browser version', () => {
  assert.equal(phone().osMajor, 27);
  const earlier = phone({ userAgent: safari.replace('Version/27.2', 'Version/26.4') });
  assert.equal(assessCompatibility(earlier, catalog).status, 'update');
  const chrome = phone({ userAgent: safari.replace('Version/27.2', 'CriOS/145.0.0.0') });
  assert.equal(chrome.osMajor, null);
  assert.equal(assessCompatibility(chrome, catalog).status, 'check-os');
  const currentChrome = phone({ userAgent: safari.replace('18_6_2', '27_2').replace('Version/27.2', 'CriOS/145.0.0.0') });
  assert.equal(currentChrome.osMajor, 27);
});

test('separates older phones from devices that can update, including overlapping screens', () => {
  const old = phone({ userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 15_8) Version/15.8 Mobile/15E148 Safari/604.1', width: 320, height: 568, pixelRatio: 2 });
  assert.equal(assessCompatibility(old, catalog).status, 'unsupported');
  assert.equal(assessCompatibility(phone({ width: 320, height: 568, pixelRatio: 2 }), catalog).status, 'check-model');
  const shared = phone({ width: 375, height: 667, pixelRatio: 2 });
  assert.ok(shared.candidates.includes('iPhone 8'));
  assert.ok(shared.candidates.includes('iPhone SE (3rd generation)'));
  assert.equal(assessCompatibility(shared, catalog).status, 'check-model');
  assert.equal(assessCompatibility(shared, catalog, 'iPhone 8').status, 'unsupported');
});

test('offers a fallback for unfamiliar sizes without guessing a model', () => {
  const unknown = phone({ width: 501, height: 901 });
  assert.deepEqual(unknown.candidates, []);
  assert.equal(assessCompatibility(unknown, catalog).status, 'check-model');
  assert.equal(assessCompatibility(unknown, catalog, 'not a model').depth, null);
});

test('every catalog entry has a display profile and every profile is in the catalog', () => {
  assert.deepEqual([...new Set(displayModels)].sort(), [...catalog.keys()].sort());
});
