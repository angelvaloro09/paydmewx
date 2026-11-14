/**
 * PaydMex — Progressive Word Scroll Reveal (js/scroll-reveal.js)
 * Wraps words of [data-scroll-words] elements in <span class="sw"> within the
 * readable text tree (no duplicate text, read once by screen readers).
 * Drives per-element --p custom property via IntersectionObserver + rAF.
 */
(function () {
  'use strict';

  const targets = Array.from(document.querySelectorAll('[data-scroll-words]'));
  if (!targets.length) return;

  const reducedMotionQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
  const STAGGER_SPREAD = 0.55;

  function collectTokens(node, inheritedEmph, out) {
    if (node.nodeType === Node.TEXT_NODE) {
      const chunks = (node.nodeValue || '').trim().split(/\s+/).filter(Boolean);
      for (let i = 0; i < chunks.length; i++) {
        out.push({ word: chunks[i], emph: inheritedEmph });
      }
      return;
    }
    if (node.nodeType === Node.ELEMENT_NODE) {
      const isEmph = inheritedEmph || node.hasAttribute('data-emph');
      const children = node.childNodes;
      for (let i = 0; i < children.length; i++) {
        collectTokens(children[i], isEmph, out);
      }
    }
  }

  function wrapWords(el) {
    const tokens = [];
    const children = el.childNodes;
    for (let i = 0; i < children.length; i++) {
      collectTokens(children[i], el.hasAttribute('data-emph'), tokens);
    }
    if (!tokens.length) return;

    const total = tokens.length;
    const denom = Math.max(1, total - 1);
    const frag = document.createDocumentFragment();

    for (let i = 0; i < total; i++) {
      if (i > 0) {
        frag.appendChild(document.createTextNode(' '));
      }
      const span = document.createElement('span');
      span.className = 'sw';
      if (tokens[i].emph) {
        span.setAttribute('data-emph', '');
      }
      const offset = (i / denom) * STAGGER_SPREAD;
      span.style.setProperty('--o', offset.toFixed(3));
      span.textContent = tokens[i].word;
      frag.appendChild(span);
    }

    el.textContent = '';
    el.appendChild(frag);
  }

  for (let i = 0; i < targets.length; i++) {
    wrapWords(targets[i]);
  }

  function setFinalColors() {
    for (let i = 0; i < targets.length; i++) {
      targets[i].style.setProperty('--p', '1');
    }
  }

  if (reducedMotionQuery.matches) {
    setFinalColors();
    return;
  }

  const activeElements = new Set();
  let rafId = 0;

  // Text already visible in the first viewport (hero) stays in its final color:
  // nobody has scrolled yet, so a dimmed state would only hurt legibility.
  const initialVh = window.innerHeight || document.documentElement.clientHeight || 1;
  const aboveFold = new Set();
  for (let i = 0; i < targets.length; i++) {
    if (targets[i].getBoundingClientRect().top + window.scrollY < initialVh * 0.85) {
      aboveFold.add(targets[i]);
    }
  }

  function computeProgress(el, vh, remainingScroll) {
    if (aboveFold.has(el)) return 1;
    const rect = el.getBoundingClientRect();
    const totalTravel = vh + rect.height;
    if (totalTravel <= 0) return 1;

    const startTop = vh - 0.2 * totalTravel;
    const idealEndTop = vh - 0.8 * totalTravel;
    const minReachableTop = rect.top - remainingScroll - 24;
    const endTop = Math.max(idealEndTop, minReachableTop);
    const span = startTop - endTop;

    if (span <= 1) {
      return rect.top <= startTop ? 1 : 0;
    }

    const raw = (startTop - rect.top) / span;
    return Math.max(0, Math.min(1, raw));
  }

  function updateActive() {
    rafId = 0;
    if (reducedMotionQuery.matches) {
      setFinalColors();
      return;
    }
    const vh = window.innerHeight || document.documentElement.clientHeight || 1;
    const docHeight = document.documentElement.scrollHeight || vh;
    const remainingScroll = Math.max(0, docHeight - vh - window.scrollY);

    activeElements.forEach(function (el) {
      const p = computeProgress(el, vh, remainingScroll);
      el.style.setProperty('--p', p.toFixed(3));
    });
  }

  function requestTick() {
    if (!rafId && activeElements.size > 0 && !reducedMotionQuery.matches) {
      rafId = window.requestAnimationFrame(updateActive);
    }
  }

  if ('IntersectionObserver' in window) {
    const io = new IntersectionObserver(function (entries) {
      for (let i = 0; i < entries.length; i++) {
        const entry = entries[i];
        if (entry.isIntersecting) {
          activeElements.add(entry.target);
        } else {
          activeElements.delete(entry.target);
          const rect = entry.boundingClientRect;
          entry.target.style.setProperty('--p', aboveFold.has(entry.target) || rect.top < 0 ? '1' : '0');
        }
      }
      requestTick();
    }, { rootMargin: '120px 0px 120px 0px' });

    for (let i = 0; i < targets.length; i++) {
      io.observe(targets[i]);
    }
  } else {
    for (let i = 0; i < targets.length; i++) {
      activeElements.add(targets[i]);
    }
  }

  window.addEventListener('scroll', requestTick, { passive: true });
  window.addEventListener('resize', requestTick, { passive: true });

  reducedMotionQuery.addEventListener('change', function (e) {
    if (e.matches) {
      if (rafId) {
        window.cancelAnimationFrame(rafId);
        rafId = 0;
      }
      setFinalColors();
    } else {
      requestTick();
    }
  });

  updateActive();
})();
