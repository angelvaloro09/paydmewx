/**
 * PaydMex — Main Landing Interactions (js/main.js)
 * Handles:
 * 1. <meta name="app-url"> CTA wiring
 * 2. First-view width/fill animations for #comision bars and [data-fulfillment-grid] steppers
 * 3. Cliente <-> Negocio tabs (roving tabindex, Arrow/Home/End keys, 280ms slide+fade, 40px swipe)
 * 4. AI Assistant prompt chips -> canned reply typewriter (instant in reduced motion)
 */
(function () {
  'use strict';

  const reducedMotionQuery = window.matchMedia('(prefers-reduced-motion: reduce)');

  // 1. Wire CTA href from <meta name="app-url">
  const appUrlMeta = document.querySelector('meta[name="app-url"]');
  const appUrl =
    (appUrlMeta && appUrlMeta.getAttribute('content') && appUrlMeta.getAttribute('content').trim()) ||
    'https://paydmex-app.vercel.app';
  const ctaLinks = document.querySelectorAll('[data-app-cta]');
  ctaLinks.forEach(function (link) {
    link.setAttribute('href', appUrl);
  });

  // 2. First-view animations for commission bars and fulfillment steppers (motion allowed only)
  const commissionSection = document.getElementById('comision');
  const fulfillmentGrid = document.querySelector('[data-fulfillment-grid]');

  if (!reducedMotionQuery.matches && 'IntersectionObserver' in window) {
    if (commissionSection) {
      commissionSection.classList.add('is-bar-ready');
      const barObserver = new IntersectionObserver(
        function (entries, obs) {
          entries.forEach(function (entry) {
            if (entry.isIntersecting) {
              commissionSection.classList.add('is-bar-animated');
              obs.disconnect();
            }
          });
        },
        { threshold: 0.25 }
      );
      barObserver.observe(commissionSection);
    }

    if (fulfillmentGrid) {
      fulfillmentGrid.classList.add('is-stepper-ready');
      const stepperObserver = new IntersectionObserver(
        function (entries, obs) {
          entries.forEach(function (entry) {
            if (entry.isIntersecting) {
              fulfillmentGrid.classList.add('is-stepper-animated');
              obs.disconnect();
            }
          });
        },
        { threshold: 0.3 }
      );
      stepperObserver.observe(fulfillmentGrid);
    }
  }

  // 3. Cliente <-> Negocio two-tab switch with directional 280ms swap & swipe
  const modesTablist = document.querySelector('[data-modes-tablist]');
  const modesTabs = Array.from(document.querySelectorAll('.modes-tab'));
  const modesViewport = document.querySelector('[data-modes-viewport]');
  const panelCliente = document.getElementById('panel-cliente');
  const panelNegocio = document.getElementById('panel-negocio');
  let activeMode = 'cliente';
  let modeSwapTimer = null;

  function clearPanelTransitionClasses(panel) {
    if (!panel) return;
    panel.classList.remove(
      'is-leaving-left',
      'is-entering-right',
      'is-leaving-right',
      'is-entering-left'
    );
  }

  function activateMode(nextMode, focusTab) {
    if (!modesTablist || !panelCliente || !panelNegocio) return;

    modesTabs.forEach(function (tab) {
      const isSelected = tab.getAttribute('data-mode') === nextMode;
      tab.setAttribute('aria-selected', isSelected ? 'true' : 'false');
      tab.setAttribute('tabindex', isSelected ? '0' : '-1');
      if (isSelected && focusTab) {
        tab.focus();
      }
    });

    if (nextMode === activeMode) return;
    const prevMode = activeMode;
    activeMode = nextMode;
    modesTablist.setAttribute('data-active-mode', nextMode);

    if (modeSwapTimer !== null) {
      window.clearTimeout(modeSwapTimer);
      modeSwapTimer = null;
    }

    clearPanelTransitionClasses(panelCliente);
    clearPanelTransitionClasses(panelNegocio);

    const outgoing = prevMode === 'cliente' ? panelCliente : panelNegocio;
    const incoming = nextMode === 'cliente' ? panelCliente : panelNegocio;

    if (reducedMotionQuery.matches) {
      incoming.hidden = false;
      outgoing.hidden = true;
      return;
    }

    const forward = prevMode === 'cliente' && nextMode === 'negocio';
    outgoing.hidden = false;
    incoming.hidden = false;

    outgoing.classList.add(forward ? 'is-leaving-left' : 'is-leaving-right');
    incoming.classList.add(forward ? 'is-entering-right' : 'is-entering-left');

    modeSwapTimer = window.setTimeout(function () {
      modeSwapTimer = null;
      clearPanelTransitionClasses(outgoing);
      clearPanelTransitionClasses(incoming);
      outgoing.hidden = true;
      incoming.hidden = false;
    }, 280);
  }

  modesTabs.forEach(function (tab) {
    tab.addEventListener('click', function () {
      const mode = tab.getAttribute('data-mode') || 'cliente';
      activateMode(mode, false);
    });

    tab.addEventListener('keydown', function (e) {
      if (e.key === 'ArrowRight' || e.key === 'ArrowLeft') {
        e.preventDefault();
        const next = activeMode === 'cliente' ? 'negocio' : 'cliente';
        activateMode(next, true);
      } else if (e.key === 'Home') {
        e.preventDefault();
        activateMode('cliente', true);
      } else if (e.key === 'End') {
        e.preventDefault();
        activateMode('negocio', true);
      }
    });
  });

  if (modesViewport) {
    let swipeStartX = 0;
    let swipeStartY = 0;
    let isSwiping = false;

    modesViewport.addEventListener('pointerdown', function (e) {
      swipeStartX = e.clientX;
      swipeStartY = e.clientY;
      isSwiping = true;
    });

    modesViewport.addEventListener('pointerup', function (e) {
      if (!isSwiping) return;
      isSwiping = false;
      const dx = e.clientX - swipeStartX;
      const dy = e.clientY - swipeStartY;
      if (Math.abs(dx) >= 40 && Math.abs(dx) > Math.abs(dy)) {
        if (dx < 0 && activeMode === 'cliente') {
          activateMode('negocio', false);
        } else if (dx > 0 && activeMode === 'negocio') {
          activateMode('cliente', false);
        }
      }
    });

    modesViewport.addEventListener('pointercancel', function () {
      isSwiping = false;
    });
  }

  // 4. AI Assistant prompt chips -> canned reply
  const PROMPTS = [
    {
      prompt: '«Vendí 3 tacos de pastor»',
      reply:
        'Listo: armé el cobro por $75.00 (3× Tacos de pastor) y preparé el QR CoDi. Al pagarse, quedarán 27 órdenes disponibles en tu inventario.'
    },
    {
      prompt: '«¿Qué se me está acabando?»',
      reply:
        'Tienes 2 productos por agotarse: Tortilla de maíz (quedan 4 paquetes) y Agua de horchata (quedan 3 litros). ¿Los agrego a tu lista para surtir?'
    },
    {
      prompt: '«¿Cuánto vendí hoy?»',
      reply:
        'Hoy llevas $1,420.00 MXN en 18 cobros confirmados por CoDi. Tu producto más vendido es Orden de tacos al pastor (11 órdenes).'
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
