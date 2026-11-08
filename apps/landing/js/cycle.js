/**
 * PaydMex — "Un ciclo que no se detiene" Hover-Expanding Row & Accordion (js/cycle.js)
 * - 4 step cards in one row on desktop (>= 900 px), vertical accordion on mobile (< 900 px) or 200% text scale
 * - Default active: 01 (Cataloga)
 * - Activation: mouse hover (pointerenter with pointerType === 'mouse', 80 ms delay), keyboard focus, click/tap
 * - Last active card stays active when pointer leaves (no auto-advance, no autoplay, no scroll listeners)
 * - Scene animations replay from start each time a card activates; cleared on deactivate; static final state under prefers-reduced-motion
 */
(function () {
  'use strict';

  const section = document.querySelector('[data-cycle-section]');
  if (!section) return;

  const loop = section.querySelector('[data-cycle-loop]');
  const loopDot = document.getElementById('cycle-loop-dot');
  const loopFill = document.getElementById('cycle-loop-fill');
  const nodes = Array.from(section.querySelectorAll('[data-cycle-node]'));
  const row = section.querySelector('[data-cycle-row]');
  const cards = Array.from(section.querySelectorAll('[data-cycle-card]'));

  if (!row || !cards.length) return;

  const heads = cards.map(function (card) {
    return card.querySelector('.cycle-head');
  });
  const bodies = cards.map(function (card) {
    return card.querySelector('.cycle-body');
  });

  const catalogCountEl = section.querySelector('[data-catalog-count]');
  const restockCountEl = section.querySelector('[data-restock-count]');
  const deliveryWordEl = section.querySelector('[data-delivery-word]');
  const deliveryBadgeEl = section.querySelector('[data-delivery-badge]');
  const deliveryDots = Array.from(section.querySelectorAll('[data-delivery-dot]'));

  const DELIVERY_STATES = [
    { word: 'Preparando', state: 'prep' },
    { word: 'Listo', state: 'ready' },
    { word: 'Entregado', state: 'done' }
  ];

  const reducedMotionQuery = window.matchMedia('(prefers-reduced-motion: reduce)');

  let activeIndex = 0;
  let hoverDelayTimer = 0;
  let catalogRafId = 0;
  let restockRafId = 0;
  let cobraTimerId = 0;
  let deliveryTimerIds = [];

  function syncAccordionLayoutMode() {
    const rootFontPx = parseFloat(window.getComputedStyle(document.documentElement).fontSize) || 16;
    const shouldStack = window.innerWidth < 900 || rootFontPx > 22;
    row.classList.toggle('is-accordion', shouldStack);
  }

  function clearHoverTimer() {
    if (hoverDelayTimer) {
      window.clearTimeout(hoverDelayTimer);
      hoverDelayTimer = 0;
    }
  }

  function stopScene(index) {
    if (index === 0 && catalogRafId) {
      window.cancelAnimationFrame(catalogRafId);
      catalogRafId = 0;
    }
    if (index === 1) {
      if (cobraTimerId) {
        window.clearTimeout(cobraTimerId);
        cobraTimerId = 0;
      }
      if (cards[1]) {
        cards[1].classList.remove('is-cobra-scanning');
      }
    }
    if (index === 2 && deliveryTimerIds.length) {
      for (let i = 0; i < deliveryTimerIds.length; i++) {
        window.clearTimeout(deliveryTimerIds[i]);
      }
      deliveryTimerIds = [];
    }
    if (index === 3 && restockRafId) {
      window.cancelAnimationFrame(restockRafId);
      restockRafId = 0;
    }
  }

  function setDeliveryStep(stepIndex) {
    const clamped = Math.max(0, Math.min(DELIVERY_STATES.length - 1, stepIndex));
    const info = DELIVERY_STATES[clamped];
    if (deliveryWordEl) {
      deliveryWordEl.textContent = info.word;
    }
    if (deliveryBadgeEl) {
      deliveryBadgeEl.setAttribute('data-state', info.state);
    }
    for (let i = 0; i < deliveryDots.length; i++) {
      deliveryDots[i].classList.toggle('is-done', i <= clamped);
      deliveryDots[i].classList.toggle('is-current', i === clamped);
    }
  }

  function setSceneFinalState(index) {
    stopScene(index);
    if (index === 0 && catalogCountEl) {
      catalogCountEl.textContent = catalogCountEl.getAttribute('data-count-to') || '32';
    } else if (index === 1 && cards[1]) {
      cards[1].classList.remove('is-cobra-scanning');
    } else if (index === 2) {
      setDeliveryStep(2);
    } else if (index === 3 && restockCountEl) {
      restockCountEl.textContent = restockCountEl.getAttribute('data-count-to') || '24';
    }
  }

  function animateNumber(el, durationMs, assignRaf) {
    if (!el) return;
    const fromVal = parseInt(el.getAttribute('data-count-from') || '0', 10);
    const toVal = parseInt(el.getAttribute('data-count-to') || '0', 10);

    if (reducedMotionQuery.matches) {
      el.textContent = String(toVal);
      return;
    }

    el.textContent = String(fromVal);
    const start = performance.now();

    function tick(now) {
      if (reducedMotionQuery.matches) {
        el.textContent = String(toVal);
        assignRaf(0);
        return;
      }
      const progress = Math.min(1, (now - start) / durationMs);
      const eased = 1 - Math.pow(1 - progress, 3);
      const current = Math.round(fromVal + (toVal - fromVal) * eased);
      el.textContent = String(current);

      if (progress < 1) {
        assignRaf(window.requestAnimationFrame(tick));
      } else {
        assignRaf(0);
      }
    }

    assignRaf(window.requestAnimationFrame(tick));
  }

  function startScene(index) {
    stopScene(index);

    if (reducedMotionQuery.matches) {
      setSceneFinalState(index);
      return;
    }

    if (index === 0) {
      animateNumber(catalogCountEl, 850, function (id) {
        catalogRafId = id;
      });
    } else if (index === 1) {
      const card = cards[1];
      if (!card) return;
      card.classList.remove('is-cobra-scanning');
      void card.offsetWidth;
      card.classList.add('is-cobra-scanning');
      cobraTimerId = window.setTimeout(function () {
        cobraTimerId = 0;
        card.classList.remove('is-cobra-scanning');
      }, 1600);
    } else if (index === 2) {
      setDeliveryStep(0);
      const t1 = window.setTimeout(function () {
        setDeliveryStep(1);
      }, 1200);
      const t2 = window.setTimeout(function () {
        setDeliveryStep(2);
      }, 2400);
      deliveryTimerIds.push(t1, t2);
    } else if (index === 3) {
      animateNumber(restockCountEl, 850, function (id) {
        restockRafId = id;
      });
    }
  }

  function syncLoopConnector(index) {
    const pct = (index * 25) + 12.5;
    const scale = cards.length > 1 ? index / (cards.length - 1) : 0;

    if (loop) {
      loop.style.setProperty('--active-step', String(index));
    }
    if (loopDot) {
      loopDot.setAttribute('data-step', String(index));
      loopDot.style.left = pct + '%';
    }
    if (loopFill) {
      loopFill.setAttribute('data-step', String(index));
      loopFill.style.transform = reducedMotionQuery.matches ? 'scaleX(1)' : 'scaleX(' + scale + ')';
    }
    for (let i = 0; i < nodes.length; i++) {
      nodes[i].classList.toggle('is-active', i === index);
    }
  }

  function activateCard(index, forceReplay) {
    const target = Math.max(0, Math.min(cards.length - 1, index));
    const changed = target !== activeIndex;

    if (!changed && !forceReplay) {
      return;
    }

    for (let i = 0; i < cards.length; i++) {
      const isAct = i === target;
      cards[i].classList.toggle('is-active', isAct);
      if (heads[i]) {
        heads[i].setAttribute('aria-expanded', isAct ? 'true' : 'false');
      }
      if (bodies[i]) {
        if (isAct) {
          bodies[i].removeAttribute('inert');
          bodies[i].removeAttribute('aria-hidden');
        } else {
          bodies[i].setAttribute('inert', '');
          bodies[i].setAttribute('aria-hidden', 'true');
        }
      }
      if (!isAct) {
        setSceneFinalState(i);
      }
    }

    activeIndex = target;
    syncLoopConnector(activeIndex);
    startScene(activeIndex);
  }

  for (let i = 0; i < cards.length; i++) {
    const card = cards[i];
    const head = heads[i];

    card.addEventListener('pointerenter', function (e) {
      if (e.pointerType !== 'mouse') return;
      clearHoverTimer();
      if (activeIndex === i) return;
      hoverDelayTimer = window.setTimeout(function () {
        hoverDelayTimer = 0;
        activateCard(i, false);
      }, 80);
    });

    card.addEventListener('pointerleave', function (e) {
      if (e.pointerType !== 'mouse') return;
      clearHoverTimer();
    });

    card.addEventListener('click', function (e) {
      if (head && head.contains(e.target)) return;
      if (activeIndex !== i) {
        activateCard(i, false);
      }
    });

    if (head) {
      head.addEventListener('focus', function () {
        clearHoverTimer();
        if (activeIndex !== i) {
          activateCard(i, false);
        }
      });

      head.addEventListener('click', function () {
        clearHoverTimer();
        activateCard(i, true);
      });

      head.addEventListener('keydown', function (e) {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          clearHoverTimer();
          activateCard(i, true);
        } else if (e.key === 'ArrowRight' || e.key === 'ArrowDown') {
          e.preventDefault();
          const next = (i + 1) % heads.length;
          if (heads[next]) {
            heads[next].focus();
          }
          activateCard(next, false);
        } else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') {
          e.preventDefault();
          const prev = (i - 1 + heads.length) % heads.length;
          if (heads[prev]) {
            heads[prev].focus();
          }
          activateCard(prev, false);
        } else if (e.key === 'Home') {
          e.preventDefault();
          if (heads[0]) {
            heads[0].focus();
          }
          activateCard(0, false);
        } else if (e.key === 'End') {
          e.preventDefault();
          const last = heads.length - 1;
          if (heads[last]) {
            heads[last].focus();
          }
          activateCard(last, false);
        }
      });
    }
  }

  reducedMotionQuery.addEventListener('change', function () {
    for (let i = 0; i < cards.length; i++) {
      setSceneFinalState(i);
    }
    syncLoopConnector(activeIndex);
  });

  window.addEventListener('resize', syncAccordionLayoutMode);

  if ('ResizeObserver' in window) {
    const ro = new ResizeObserver(syncAccordionLayoutMode);
    ro.observe(document.documentElement);
    ro.observe(row);
  }

  if ('MutationObserver' in window) {
    const mo = new MutationObserver(syncAccordionLayoutMode);
    mo.observe(document.documentElement, { attributes: true, attributeFilter: ['style', 'class'] });
  }

  syncAccordionLayoutMode();
  for (let i = 0; i < cards.length; i++) {
    setSceneFinalState(i);
  }
  syncLoopConnector(0);
  startScene(0);
})();
