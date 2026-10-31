/* Copyright (C) 2026 Wachirawich Kripindakul. SPDX-License-Identifier: AGPL-3.0-or-later. See LICENSE. */
(() => {
  'use strict';
  const root = document.documentElement;
  const labels = [...document.querySelectorAll('[data-en]')].map(el => ({ el, th: el.textContent, en: el.dataset.en }));
  const attributes = [...document.querySelectorAll('[data-en-aria]')].map(el => ({ el, th: el.getAttribute('aria-label'), en: el.dataset.enAria }));
  const title = document.querySelector('title');
  const description = document.querySelector('meta[name="description"]');
  function setLanguage(next, persist = false) {
    const language = next === 'en' ? 'en' : 'th';
    root.lang = language;
    labels.forEach(item => { item.el.textContent = item[language]; });
    attributes.forEach(item => { item.el.setAttribute('aria-label', item[language]); });
    document.querySelectorAll('[data-document-language]').forEach(article => { article.hidden = article.dataset.documentLanguage !== language; });
    document.querySelectorAll('[data-language]').forEach(button => { button.setAttribute('aria-pressed', String(button.dataset.language === language)); });
    document.title = title.getAttribute(`data-title-${language}`);
    description.content = description.getAttribute(`data-description-${language}`);
    document.querySelector('meta[property="og:title"]').content = document.title;
    document.querySelector('meta[property="og:description"]').content = description.content;
    document.querySelector('meta[property="og:locale"]').content = language === 'en' ? 'en_US' : 'th_TH';
    document.querySelectorAll('a[href]').forEach(link => {
      if (link.hasAttribute('data-document-original') || link.hasAttribute('data-document-github')) {
        const source = (language === 'th' ? 'docs/th/' : '') + (link.dataset.documentOriginal || link.dataset.documentGithub);
        link.href = link.hasAttribute('data-document-github') ? `https://github.com/koomean/visionassistant/blob/main/${source}` : source;
        return;
      }
      const url = new URL(link.href, location.href);
      if (url.origin === location.origin && (url.pathname.endsWith('.html') || url.pathname.endsWith('/')) && link.getAttribute('href')[0] !== '#') {
        url.searchParams.set('lang', language);
        link.href = url.href;
      }
    });
    if (persist) {
      try { localStorage.setItem('lunav-language', language); } catch { /* URL links also carry the chosen language. */ }
      const url = new URL(location.href);
      url.searchParams.set('lang', language);
      try { history.replaceState(history.state, '', url); } catch { /* Navigation links retain the chosen language if history access is denied. */ }
    }
    window.dispatchEvent(new CustomEvent('lunav:languagechange', { detail: { language } }));
  }
  document.querySelectorAll('[data-language]').forEach(button => button.addEventListener('click', () => setLanguage(button.dataset.language, true)));
  const requested = new URLSearchParams(location.search).get('lang');
  setLanguage(root.lang, requested === 'th' || requested === 'en');
})();
