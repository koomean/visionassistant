/* Copyright (C) 2026 Wachirawich Kripindakul. SPDX-License-Identifier: AGPL-3.0-or-later. */
export const minimumIOS = 27;

// Standard portrait screen sizes in CSS pixels, plus device pixel ratio.
// Apple display specs: https://support.apple.com/en-us/108044
// Keep shared profiles together. Display Zoom or browser privacy settings may
// change the reported dimensions, so a screen match is only a suggestion.
const profiles = {
  '320x480@1': ['(original)', '3G', '3GS'],
  '320x480@2': ['4', '4s'],
  '320x568@2': ['5', '5c', '5s', 'SE (1st generation)'],
  '375x667@2': ['6', '6s', '7', '8', 'SE (2nd generation)', 'SE (3rd generation)'],
  '414x736@3': ['6 Plus', '6s Plus', '7 Plus', '8 Plus'],
  '375x812@3': ['X', 'XS', '11 Pro', '12 mini', '13 mini'],
  '360x780@3': ['12 mini', '13 mini'],
  '414x896@2': ['XR', '11'],
  '414x896@3': ['XS Max', '11 Pro Max'],
  '390x844@3': ['12', '12 Pro', '13', '13 Pro', '14', '16e', '17e'],
  '393x852@3': ['14 Pro', '15', '15 Pro', '16'],
  '402x874@3': ['16 Pro', '17', '17 Pro', '18 Pro'],
  '428x926@3': ['12 Pro Max', '13 Pro Max', '14 Plus'],
  '430x932@3': ['14 Pro Max', '15 Plus', '15 Pro Max', '16 Plus'],
  '440x956@3': ['16 Pro Max', '17 Pro Max', '18 Pro Max'],
  '420x912@3': ['Air'],
  '466x678@3': ['Duo'],
  '626x890@3': ['Duo'],
};

const names = models => models.map(model => `iPhone ${model}`);
export const displayModels = Object.values(profiles).flatMap(names);

function phoneOS(ua) {
  const reported = ua.match(/\biPhone OS (\d+)(?:[_.](\d+))?/i);
  const major = Number(reported?.[1]);
  // Modern iOS Safari freezes the OS token at 18.6.x. Safari's own
  // Version/ token tracks the iOS major; other browsers' version tokens do not.
  const safari = /\bSafari\//i.test(ua)
    && !/\b(?:CriOS|FxiOS|EdgiOS|OPiOS|OPT|DuckDuckGo|YaBrowser|GSA|Chrome|Firefox)\b/i.test(ua);
  const safariMajor = Number(ua.match(/\bVersion\/(\d+)/i)?.[1]);
  if (safari && safariMajor >= 26) return safariMajor;
  if (major >= 26 || (major > 0 && (major < 18 || (major === 18 && Number(reported[2]) < 6)))) return major;
  if (major === 18 && safari && safariMajor === 18) return major;
  return null;
}

export function detectDevice({ userAgent = '', platform = '', maxTouchPoints = 0, width, height, pixelRatio } = {}) {
  const key = `${Math.min(width, height)}x${Math.max(width, height)}@${pixelRatio}`;
  const candidates = names(profiles[key] || []);
  let kind = 'other';
  if (/\bAndroid\b/i.test(userAgent)) kind = 'android';
  else if (/\biPad\b/i.test(userAgent) || platform === 'iPad') kind = 'ipad';
  else if (/\biPod\b/i.test(userAgent) || platform === 'iPod') kind = 'other';
  else if (/\biPhone\b/i.test(userAgent) || platform === 'iPhone') kind = 'iphone';
  else if (/Mac/i.test(platform) || /Macintosh/i.test(userAgent)) {
    // Both iPad and iPhone can advertise a desktop Mac user agent. A phone-sized
    // screen gives a shortlist, but cannot establish the platform on its own.
    kind = maxTouchPoints <= 1 ? 'mac' : candidates.length ? 'apple-mobile' : 'ipad';
  }
  if (kind === 'apple-mobile') return { platform: kind, osMajor: null, candidates };
  if (kind !== 'iphone') return { platform: kind, osMajor: null, candidates: [] };
  return { platform: kind, osMajor: phoneOS(userAgent), candidates };
}

export function assessCompatibility(device, catalog, selection = '') {
  const result = { status: 'unsupported', model: null, depth: null };
  const selected = catalog.has(selection);
  if (device.platform === 'apple-mobile' && !selected) return { ...result, status: 'check-model' };
  if (device.platform !== 'iphone' && device.platform !== 'apple-mobile') return result;
  const candidates = selected ? [selection] : device.candidates.filter(model => catalog.has(model));
  const depths = candidates.map(model => catalog.get(model));
  result.model = candidates.length === 1 ? candidates[0] : null;
  if (depths.length && depths.every(depth => depth === 'legacy')) {
    return selected || (device.osMajor !== null && device.osMajor < minimumIOS)
      ? result : { status: 'check-model', model: null, depth: null };
  }

  const eligible = depths.length && depths.every(depth => depth === 'lidar' || depth === 'da3');
  if (eligible && depths.every(depth => depth === depths[0])) result.depth = depths[0];
  result.status = !eligible ? 'check-model'
    : device.osMajor === null ? 'check-os'
    : device.osMajor < minimumIOS ? 'update'
    : selected ? 'supported' : 'likely';
  return result;
}
