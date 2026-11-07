/**
 * PaydMex — Main Landing Interactions (js/main.js)
 * Handles:
 * 1. <meta name="app-url"> CTA wiring
 * 2. Facts strip one-time count-up (respects prefers-reduced-motion)
 * 3. Cliente <-> Negocio pill segmented toggle (300ms slide + keyboard arrow support)
 * 4. AI Assistant prompt chips -> canned reply typewriter (instant in reduced motion)
 */
(function () {
  'use strict';

  const reducedMotionQuery = window.matchMedia('(prefers-reduced-motion: reduce)');

  // 1. Wire CTA href from <meta name="app-url">
  const appUrlMeta = document.querySelector('meta[name="app-url"]');
  const appUrl = (appUrlMeta && appUrlMeta.getAttribute('content') && appUrlMeta.getAttribute('content').trim()) || '#';
  const ctaLinks = document.querySelectorAll('[data-app-cta]');
  ctaLinks.forEach(function (link) {
    link.setAttribute('href', appUrl);
  });

  // 2. Facts strip count-up once on first view
  const factsStrip = document.getElementById('facts-strip');
  let factsAnimated = false;

  function runFactsCountUp() {
    if (factsAnimated || !factsStrip) return;
    factsAnimated = true;

    if (reducedMotionQuery.matches) {
      return; // Leave final values as-is
    }

    const ratioEl = factsStrip.querySelector('[data-fact-type="ratio"]');
    if (!ratioEl) return;

    const targetA = parseInt(ratioEl.getAttribute('data-target-a') || '24', 10);
    const targetB = parseInt(ratioEl.getAttribute('data-target-b') || '7', 10);
    const duration = 600;
    const startTime = performance.now();

    function step(now) {
      const progress = Math.min(1, (now - startTime) / duration);
      const eased = 1 - Math.pow(1 - progress, 3);
      const curA = Math.round(targetA * eased);
      const curB = Math.round(targetB * eased);
      ratioEl.textContent = curA + '/' + curB;
      if (progress < 1 && !reducedMotionQuery.matches) {
        window.requestAnimationFrame(step);
      } else {
        ratioEl.textContent = targetA + '/' + targetB;
      }
    }

    window.requestAnimationFrame(step);
  }

  if (factsStrip && 'IntersectionObserver' in window) {
    const factsObserver = new IntersectionObserver(function (entries, obs) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          runFactsCountUp();
          obs.disconnect();
        }
      });
    }, { threshold: 0.35 });

    factsObserver.observe(factsStrip);
  }

  // 4. Segmented pill toggle (Cliente <-> Negocio)
  const segmentedControl = document.querySelector('.segmented-control');
  const segmentedBtns = document.querySelectorAll('.segmented-btn');
  const panelCliente = document.getElementById('panel-cliente');
  const panelNegocio = document.getElementById('panel-negocio');

  function activateMode(mode, focusTab) {
    if (!segmentedControl) return;
    segmentedControl.setAttribute('data-active', mode);

    segmentedBtns.forEach(function (btn) {
      const isSelected = btn.getAttribute('data-mode') === mode;
      btn.classList.toggle('is-active', isSelected);
      btn.setAttribute('aria-selected', isSelected ? 'true' : 'false');
      if (isSelected && focusTab) {
        btn.focus();
      }
    });

    if (panelCliente && panelNegocio) {
      if (mode === 'cliente') {
        panelCliente.hidden = false;
        panelNegocio.hidden = true;
      } else {
        panelCliente.hidden = true;
        panelNegocio.hidden = false;
      }
    }
  }

  segmentedBtns.forEach(function (btn) {
    btn.addEventListener('click', function () {
      const mode = btn.getAttribute('data-mode') || 'cliente';
      activateMode(mode, false);
    });

    btn.addEventListener('keydown', function (e) {
      if (e.key === 'ArrowRight' || e.key === 'ArrowLeft') {
        e.preventDefault();
        const current = btn.getAttribute('data-mode');
        const next = current === 'cliente' ? 'negocio' : 'cliente';
        activateMode(next, true);
      }
    });
  });

  // 5. AI Assistant prompt chips -> canned reply
  const PROMPTS = [
    {
      prompt: '«Vendí 3 tacos de pastor»',
      reply: 'Listo: armé el cobro por $75.00 (3× Tacos de pastor) y preparé el QR CoDi. Al pagarse, quedarán 27 órdenes disponibles en tu inventario.'
    },
    {
      prompt: '«¿Qué se me está acabando?»',
      reply: 'Tienes 2 productos por agotarse: Tortilla de maíz (quedan 4 paquetes) y Agua de horchata (quedan 3 litros). ¿Los agrego a tu lista para surtir?'
    },
    {
      prompt: '«¿Cuánto vendí hoy?»',
      reply: 'Hoy llevas $1,420.00 MXN en 18 cobros confirmados por CoDi. Tu producto más vendido es Orden de tacos al pastor (11 órdenes).'
    }
  ];

  const promptChips = document.querySelectorAll('.prompt-chip');
  const userBubble = document.getElementById('ai-user-bubble');
  const replyText = document.getElementById('ai-reply-text');
  let typingTimer = null;

  function selectPrompt(index) {
    const item = PROMPTS[index];
    if (!item || !userBubble || !replyText) return;

    promptChips.forEach(function (chip, idx) {
      chip.setAttribute('aria-pressed', idx === index ? 'true' : 'false');
    });

    userBubble.textContent = item.prompt;

    if (typingTimer) {
      window.clearInterval(typingTimer);
      typingTimer = null;
    }

    if (reducedMotionQuery.matches) {
      replyText.textContent = item.reply;
      return;
    }

    replyText.textContent = '';
    let charIndex = 0;
    const fullText = item.reply;

    typingTimer = window.setInterval(function () {
      charIndex += 3;
      if (charIndex >= fullText.length) {
        replyText.textContent = fullText;
        window.clearInterval(typingTimer);
        typingTimer = null;
      } else {
        replyText.textContent = fullText.slice(0, charIndex);
      }
    }, 18);
  }

  promptChips.forEach(function (chip) {
    chip.setAttribute('aria-pressed', chip.getAttribute('data-prompt-index') === '0' ? 'true' : 'false');
    chip.addEventListener('click', function () {
      const idx = parseInt(chip.getAttribute('data-prompt-index') || '0', 10);
      selectPrompt(idx);
    });
  });
})();
