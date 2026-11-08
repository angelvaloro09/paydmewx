/**
 * PaydMex — Four-Stage Cycle Capsules (js/cycle.js)
 * 1. Scroll-driven stage selection across 4 equal segments of sticky track (>= 760px)
 * 2. WAI-ARIA tablist: roving tabindex, ArrowLeft/Right/Up/Down/Home/End, aria-selected, hidden+inert
 * 3. Smooth scroll sync on click/key with scroll-listener suppression
 * 4. SVG loop connector (desktop) & vertical rail (mobile) stroke-dashoffset + dot via getPointAtLength
 * 5. Reduced motion: all 4 capsules expanded static, loop drawn fully, no dot travel
 */
(function () {
  'use strict';

  const section = document.querySelector('[data-cycle-section]');
  if (!section) return;

  const track = section.querySelector('[data-cycle-track]');
  const capsules = Array.from(section.querySelectorAll('[data-cycle-capsule]'));
  const tabs = Array.from(section.querySelectorAll('[data-cycle-tab]'));
  const panels = Array.from(section.querySelectorAll('[data-cycle-panel]'));
  const loopPath = document.getElementById('cycle-loop-path');
  const loopDot = document.getElementById('cycle-loop-dot');
  const railPath = document.getElementById('cycle-rail-path');
  const railDot = document.getElementById('cycle-rail-dot');

  const count = capsules.length;
  if (!count) return;

  const reducedMotionQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
  const desktopQuery = window.matchMedia('(min-width: 760px)');

  let activeIndex = 0;
  let suppressUntil = 0;
  let suppressTimer = 0;
  let isInView = true;
  let scrollRafId = 0;

  let loopLen = 0;
  let railLen = 0;
  let curProg = 0.25;
  let tgtProg = 0.25;
  let animRafId = 0;
  let animStart = 0;
  let animFrom = 0.25;

  function initLen(el) {
    if (!el || typeof el.getTotalLength !== 'function') return 0;
    try {
      const len = el.getTotalLength();
      el.style.strokeDasharray = len.toFixed(2);
      return len;
    } catch (_) {
      return 0;
    }
  }

  function measurePaths() {
    loopLen = initLen(loopPath);
    railLen = initLen(railPath);
  }

  function renderPath(pathEl, dotEl, len, prog, isStatic) {
    if (!pathEl || len <= 0) return;
    const p = isStatic ? 1 : Math.max(0.06, Math.min(1, prog));
    pathEl.style.strokeDashoffset = (len * (1 - p)).toFixed(2);
    if (dotEl && !isStatic && typeof pathEl.getPointAtLength === 'function') {
      try {
        const pt = pathEl.getPointAtLength(p * len);
        dotEl.setAttribute('cx', pt.x.toFixed(2));
        dotEl.setAttribute('cy', pt.y.toFixed(2));
      } catch (_) {}
    }
  }

  function renderConnectors(prog) {
    const isReduced = reducedMotionQuery.matches;
    renderPath(loopPath, loopDot, loopLen, prog, isReduced);
    renderPath(railPath, railDot, railLen, prog, isReduced);
  }

  function animateConnectors(nextProg) {
    tgtProg = nextProg;
    if (reducedMotionQuery.matches) {
      if (animRafId) cancelAnimationFrame(animRafId);
      animRafId = 0;
      curProg = 1;
      renderConnectors(1);
      return;
    }
    animFrom = curProg;
    animStart = performance.now();
    if (animRafId) cancelAnimationFrame(animRafId);

    function step(now) {
      const t = Math.min(1, (now - animStart) / 420);
      curProg = animFrom + (tgtProg - animFrom) * (1 - Math.pow(1 - t, 3));
      renderConnectors(curProg);
      animRafId = t < 1 ? requestAnimationFrame(step) : 0;
    }
    animRafId = requestAnimationFrame(step);
  }

  function applyState(index, focusTab) {
    const isReduced = reducedMotionQuery.matches;
    activeIndex = Math.max(0, Math.min(count - 1, index));

    for (let i = 0; i < count; i++) {
      const isSelected = i === activeIndex;
      const isExpanded = isReduced || isSelected;
      const capsule = capsules[i];
      const tab = tabs[i];
      const panel = panels[i];

      if (capsule) capsule.classList.toggle('is-active', isExpanded);
      if (tab) {
        tab.setAttribute('aria-selected', isSelected ? 'true' : 'false');
        tab.setAttribute('tabindex', isSelected ? '0' : '-1');
        if (focusTab && isSelected) tab.focus({ preventScroll: true });
      }
      if (panel) {
        if (isExpanded) {
          panel.removeAttribute('hidden');
          panel.removeAttribute('inert');
          panel.inert = false;
        } else {
          panel.setAttribute('hidden', '');
          panel.setAttribute('inert', '');
          panel.inert = true;
        }
      }
    }
    animateConnectors((activeIndex + 1) / count);
  }

  function handleUserSelect(index, focusTab) {
    applyState(index, Boolean(focusTab));
    if (reducedMotionQuery.matches || !desktopQuery.matches || !track) return;

    const rect = track.getBoundingClientRect();
    const scrollable = track.offsetHeight - window.innerHeight;
    if (scrollable > 20) {
      const segProg = index === 0 ? 0.06 : (index + 0.5) / count;
      const targetY = rect.top + window.scrollY + scrollable * segProg;
      suppressUntil = performance.now() + 780;
      if (suppressTimer) clearTimeout(suppressTimer);
      suppressTimer = window.setTimeout(function () {
        suppressUntil = 0;
        suppressTimer = 0;
      }, 780);
      window.scrollTo({ top: Math.max(0, Math.round(targetY)), behavior: 'smooth' });
    }
  }

  for (let i = 0; i < tabs.length; i++) {
    tabs[i].addEventListener('click', function () {
      handleUserSelect(i, false);
    });
    tabs[i].addEventListener('keydown', function (e) {
      let next = -1;
      if (e.key === 'ArrowRight' || e.key === 'ArrowDown') next = (i + 1) % count;
      else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') next = (i - 1 + count) % count;
      else if (e.key === 'Home') next = 0;
      else if (e.key === 'End') next = count - 1;
      if (next !== -1) {
        e.preventDefault();
        handleUserSelect(next, true);
      }
    });
  }

  for (let i = 0; i < capsules.length; i++) {
    capsules[i].addEventListener('click', function (e) {
      if (activeIndex !== i && (!tabs[i] || !tabs[i].contains(e.target))) {
        handleUserSelect(i, false);
      }
    });
  }

  function updateFromScroll() {
    scrollRafId = 0;
    if (!isInView || reducedMotionQuery.matches || !desktopQuery.matches || !track) return;
    if (performance.now() < suppressUntil) return;

    const rect = track.getBoundingClientRect();
    const scrollable = rect.height - window.innerHeight;
    if (scrollable <= 0) return;

    const raw = -rect.top / scrollable;
    if (raw < -0.05 || raw > 1.05) return;

    const seg = Math.floor(Math.max(0, Math.min(0.9999, raw)) * count);
    if (seg !== activeIndex) applyState(seg, false);
  }

  function onScroll() {
    if (isInView && !reducedMotionQuery.matches && desktopQuery.matches && !scrollRafId) {
      scrollRafId = requestAnimationFrame(updateFromScroll);
    }
  }

  if ('IntersectionObserver' in window) {
    new IntersectionObserver(
      function (entries) {
        for (let i = 0; i < entries.length; i++) isInView = entries[i].isIntersecting;
        if (isInView) onScroll();
      },
      { rootMargin: '150px 0px 150px 0px' }
    ).observe(section);
  }

  window.addEventListener('scroll', onScroll, { passive: true });
  if ('onscrollend' in window) {
    window.addEventListener('scrollend', function () {
      suppressUntil = 0;
    }, { passive: true });
  }

  function onModeChange() {
    measurePaths();
    applyState(activeIndex, false);
  }

  window.addEventListener('resize', onModeChange, { passive: true });
  reducedMotionQuery.addEventListener('change', onModeChange);
  desktopQuery.addEventListener('change', onModeChange);

  measurePaths();
  applyState(0, false);
})();
