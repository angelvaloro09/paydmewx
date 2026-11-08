/**
 * PaydMex — Four-Step Business Cycle Cards (js/cycle.js)
 * 1. Hover, focus, and tap interaction across the 4 step cards ([data-cycle-card])
 * 2. Loop header ([data-cycle-loop]): highlights active node ([data-cycle-node]) in --brand,
 *    travels #cycle-loop-dot to hovered/focused card, and returns to node 01 when pointer leaves all cards
 * 3. Live mini-scene animations:
 *    - 01 Cataloga: product rows slide in + stock chips ([data-stock-target]) count up
 *    - 02 Cobra: QR scan line sweep + status flip from "Esperando pago" to "Pagado"
 *    - 03 Entrega: sequential status chip illumination + progress bar fill
 *    - 04 Reabastece: alert pulse + pill check flip + stock rise (.cycle-restock-num 4 -> 24)
 * 4. Touch viewport trigger (IntersectionObserver, threshold: 0.4) plays once on entry and again on tap
 * 5. Reduced motion: static final states, no counting or travelling dot
 */
(function () {
  'use strict';

  const section = document.querySelector('[data-cycle-section]');
  if (!section) return;

  const loop = section.querySelector('[data-cycle-loop]');
  const grid = section.querySelector('[data-cycle-grid]');
  const loopDot = document.getElementById('cycle-loop-dot');
  const loopFill = document.getElementById('cycle-loop-fill');
  const nodes = Array.from(section.querySelectorAll('[data-cycle-node]'));
  const cards = Array.from(section.querySelectorAll('[data-cycle-card]'));
  const stockChips = Array.from(section.querySelectorAll('[data-stock-target]'));
  const restockNum = section.querySelector('.cycle-restock-num');

  if (!cards.length) return;

  const reducedMotionQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
  const touchQuery = window.matchMedia('(hover: none), (pointer: coarse)');

  let activeStep = 0;
  let hoveredCardIndex = -1;
  let catalogRafId = 0;
  let restockRafId = 0;
  let restockDelayTimer = 0;
  const clearTimers = new Map();

  function cancelCardAnimations(index) {
    if (index === 0 && catalogRafId) {
      window.cancelAnimationFrame(catalogRafId);
      catalogRafId = 0;
    }
    if (index === 3) {
      if (restockDelayTimer) {
        window.clearTimeout(restockDelayTimer);
        restockDelayTimer = 0;
      }
      if (restockRafId) {
        window.cancelAnimationFrame(restockRafId);
        restockRafId = 0;
      }
    }
    if (clearTimers.has(index)) {
      window.clearTimeout(clearTimers.get(index));
      clearTimers.delete(index);
    }
  }

  function setStaticFinalValues() {
    for (let i = 0; i < stockChips.length; i++) {
      const target = parseInt(stockChips[i].getAttribute('data-stock-target') || '0', 10);
      stockChips[i].textContent = target + ' disp.';
    }
    if (restockNum) {
      const toVal = parseInt(restockNum.getAttribute('data-restock-to') || '24', 10);
      restockNum.textContent = String(toVal);
    }
  }

  function setRestValuesForCard(index) {
    if (reducedMotionQuery.matches) {
      setStaticFinalValues();
      return;
    }
    if (index === 0) {
      for (let i = 0; i < stockChips.length; i++) {
        const target = parseInt(stockChips[i].getAttribute('data-stock-target') || '0', 10);
        stockChips[i].textContent = target + ' disp.';
      }
    }
    if (index === 3 && restockNum) {
      const fromVal = parseInt(restockNum.getAttribute('data-restock-from') || '4', 10);
      restockNum.textContent = String(fromVal);
    }
  }

  function setLoopNode(index) {
    activeStep = Math.max(0, Math.min(cards.length - 1, index));
    const pct = (activeStep * 25) + 12.5;
    const scale = cards.length > 1 ? activeStep / (cards.length - 1) : 0;

    if (loop) {
      loop.style.setProperty('--active-step', String(activeStep));
    }
    if (loopDot) {
      loopDot.setAttribute('data-step', String(activeStep));
      loopDot.style.left = pct + '%';
    }
    if (loopFill) {
      loopFill.setAttribute('data-step', String(activeStep));
      if (!reducedMotionQuery.matches) {
        loopFill.style.transform = 'scaleX(' + scale + ')';
      } else {
        loopFill.style.transform = 'scaleX(1)';
      }
    }
    for (let i = 0; i < nodes.length; i++) {
      nodes[i].classList.toggle('is-active', i === activeStep);
    }
  }

  function syncLoopToActiveCard() {
    if (hoveredCardIndex >= 0 && hoveredCardIndex < cards.length) {
      setLoopNode(hoveredCardIndex);
      return;
    }
    for (let i = 0; i < cards.length; i++) {
      if (document.activeElement === cards[i]) {
        setLoopNode(i);
        return;
      }
    }
    for (let i = 0; i < cards.length; i++) {
      if (cards[i].classList.contains('is-active')) {
        setLoopNode(i);
        return;
      }
    }
    setLoopNode(0);
  }

  function runCatalogCountUp() {
    if (reducedMotionQuery.matches || !stockChips.length) {
      setStaticFinalValues();
      return;
    }
    if (catalogRafId) {
      window.cancelAnimationFrame(catalogRafId);
      catalogRafId = 0;
    }

    const duration = 520;
    const start = performance.now();

    function tick(now) {
      if (reducedMotionQuery.matches) {
        setStaticFinalValues();
        catalogRafId = 0;
        return;
      }
      const elapsed = now - start;
      let allDone = true;

      for (let i = 0; i < stockChips.length; i++) {
        const chip = stockChips[i];
        const target = parseInt(chip.getAttribute('data-stock-target') || '0', 10);
        const delay = i * 70;
        const local = Math.max(0, Math.min(1, (elapsed - delay) / duration));
        if (local < 1) allDone = false;
        const eased = 1 - Math.pow(1 - local, 3);
        const val = Math.round(target * eased);
        chip.textContent = val + ' disp.';
      }

      if (!allDone) {
        catalogRafId = window.requestAnimationFrame(tick);
      } else {
        catalogRafId = 0;
      }
    }

    catalogRafId = window.requestAnimationFrame(tick);
  }

  function runRestockRise() {
    if (!restockNum) return;
    const fromVal = parseInt(restockNum.getAttribute('data-restock-from') || '4', 10);
    const toVal = parseInt(restockNum.getAttribute('data-restock-to') || '24', 10);

    if (reducedMotionQuery.matches) {
      restockNum.textContent = String(toVal);
      return;
    }

    if (restockDelayTimer) {
      window.clearTimeout(restockDelayTimer);
      restockDelayTimer = 0;
    }
    if (restockRafId) {
      window.cancelAnimationFrame(restockRafId);
      restockRafId = 0;
    }

    restockNum.textContent = String(fromVal);

    restockDelayTimer = window.setTimeout(function () {
      restockDelayTimer = 0;
      const duration = 420;
      const start = performance.now();

      function tick(now) {
        if (reducedMotionQuery.matches) {
          restockNum.textContent = String(toVal);
          restockRafId = 0;
          return;
        }
        const p = Math.min(1, (now - start) / duration);
        const eased = 1 - Math.pow(1 - p, 3);
        const cur = Math.round(fromVal + (toVal - fromVal) * eased);
        restockNum.textContent = String(cur);
        if (p < 1) {
          restockRafId = window.requestAnimationFrame(tick);
        } else {
          restockRafId = 0;
        }
      }

      restockRafId = window.requestAnimationFrame(tick);
    }, 260);
  }

  function triggerCardAnimation(index, keepActiveDurationMs) {
    const card = cards[index];
    if (!card) return;

    for (let j = 0; j < cards.length; j++) {
      if (j !== index && hoveredCardIndex !== j && document.activeElement !== cards[j]) {
        cards[j].classList.remove('is-active');
        cards[j].classList.remove('is-animating');
      }
    }

    setLoopNode(index);
    cancelCardAnimations(index);

    card.classList.add('is-active');

    if (reducedMotionQuery.matches) {
      card.classList.remove('is-animating');
      setStaticFinalValues();
      return;
    }

    card.classList.remove('is-animating');
    void card.offsetWidth;
    card.classList.add('is-animating');

    if (index === 0) {
      runCatalogCountUp();
    } else if (index === 3) {
      runRestockRise();
    }

    if (keepActiveDurationMs && keepActiveDurationMs > 0) {
      const timerId = window.setTimeout(function () {
        clearTimers.delete(index);
        if (document.activeElement !== card && hoveredCardIndex !== index) {
          card.classList.remove('is-active');
          card.classList.remove('is-animating');
          setRestValuesForCard(index);
          syncLoopToActiveCard();
        }
      }, keepActiveDurationMs);
      clearTimers.set(index, timerId);
    }
  }

  function deactivateCard(index) {
    const card = cards[index];
    if (!card) return;
    cancelCardAnimations(index);
    card.classList.remove('is-active');
    card.classList.remove('is-animating');
    setRestValuesForCard(index);
    syncLoopToActiveCard();
  }

  for (let i = 0; i < cards.length; i++) {
    const card = cards[i];

    card.addEventListener('mouseenter', function () {
      hoveredCardIndex = i;
      triggerCardAnimation(i, 0);
    });

    card.addEventListener('mouseleave', function () {
      if (hoveredCardIndex === i) {
        hoveredCardIndex = -1;
      }
      if (document.activeElement !== card) {
        deactivateCard(i);
      } else {
        syncLoopToActiveCard();
      }
    });

    card.addEventListener('focusin', function () {
      triggerCardAnimation(i, 0);
    });

    card.addEventListener('focusout', function () {
      window.setTimeout(function () {
        if (hoveredCardIndex !== i && document.activeElement !== card) {
          deactivateCard(i);
        }
      }, 0);
    });

    card.addEventListener('click', function () {
      triggerCardAnimation(i, 1400);
    });

    card.addEventListener('keydown', function (e) {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        triggerCardAnimation(i, 1400);
      } else if (e.key === 'ArrowRight' || e.key === 'ArrowDown') {
        e.preventDefault();
        const next = (i + 1) % cards.length;
        cards[next].focus();
      } else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') {
        e.preventDefault();
        const prev = (i - 1 + cards.length) % cards.length;
        cards[prev].focus();
      }
    });
  }

  if (grid) {
    grid.addEventListener('mouseleave', function () {
      hoveredCardIndex = -1;
      syncLoopToActiveCard();
    });
  }

  if ('IntersectionObserver' in window) {
    const seenCards = new WeakSet();
    const cardObserver = new IntersectionObserver(
      function (entries) {
        for (let i = 0; i < entries.length; i++) {
          const entry = entries[i];
          if (entry.isIntersecting && !seenCards.has(entry.target)) {
            seenCards.add(entry.target);
            if (touchQuery.matches && !reducedMotionQuery.matches) {
              const idx = cards.indexOf(entry.target);
              if (idx !== -1) {
                triggerCardAnimation(idx, 1400);
              }
            }
          }
        }
      },
      { threshold: 0.4 }
    );

    for (let i = 0; i < cards.length; i++) {
      cardObserver.observe(cards[i]);
    }
  }

  function syncMotionMode() {
    if (reducedMotionQuery.matches) {
      for (let i = 0; i < cards.length; i++) {
        cancelCardAnimations(i);
        cards[i].classList.remove('is-animating');
      }
      setStaticFinalValues();
    } else {
      setRestValuesForCard(3);
    }
    setLoopNode(activeStep);
  }

  reducedMotionQuery.addEventListener('change', syncMotionMode);

  setLoopNode(0);
  syncMotionMode();
})();
