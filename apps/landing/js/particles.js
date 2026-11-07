/**
 * PaydMex — Hero Glyph-Particle Sphere (js/particles.js)
 * Renders 380 currency/math glyphs ($ ¢ ₱ +) distributed on a Fibonacci sphere.
 * Features: slow rotation, pointer parallax, DPR capped at 2,
 * left-to-right scrim for headline contrast, front hemisphere brand glow,
 * IntersectionObserver off-screen pause, single static frame when prefers-reduced-motion: reduce.
 */
(function () {
  'use strict';

  const canvas = document.getElementById('hero-particles');
  if (!canvas) return;

  const ctx = canvas.getContext('2d');
  if (!ctx) return;

  const GLYPHS = ['$', '¢', '₱', '+'];
  const COUNT = 380;
  const GOLDEN_ANGLE = Math.PI * (3 - Math.sqrt(5));

  const FRONT_COLOR = '#19E36B';
  const FRONT_GLOW_COLOR = 'rgba(25, 227, 107, 0.4)';
  const FRONT_SHADOW_BLUR = 8;
  const REAR_COLOR = '#F5F4F0';

  const reducedMotionQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
  let isReducedMotion = reducedMotionQuery.matches;

  // Build Fibonacci sphere points and reusable projection buffers
  const points = new Array(COUNT);
  const rearQueue = new Array(COUNT);
  const frontQueue = new Array(COUNT);

  for (let i = 0; i < COUNT; i++) {
    const y = 1 - (i / (COUNT - 1)) * 2;
    const radiusAtY = Math.sqrt(1 - y * y);
    const theta = GOLDEN_ANGLE * i;
    points[i] = {
      x: Math.cos(theta) * radiusAtY,
      y: y,
      z: Math.sin(theta) * radiusAtY,
      glyph: GLYPHS[i % GLYPHS.length],
      screenX: 0,
      screenY: 0,
      alpha: 0
    };
  }

  let width = 0;
  let height = 0;
  let dpr = 1;
  let rotY = 0.4;
  let rotX = 0.18;
  let targetParallaxX = 0;
  let targetParallaxY = 0;
  let currentParallaxX = 0;
  let currentParallaxY = 0;
  let isVisible = true;
  let rafId = null;

  function computeScrimFactor(screenX) {
    const xNorm = screenX / width;
    // Fully faded behind the text column, full strength on the right third.
    if (xNorm <= 0.52) return 0.10;
    if (xNorm >= 0.84) return 1.0;
    return 0.10 + ((xNorm - 0.52) / 0.32) * 0.90;
  }

  function resize() {
    const parent = canvas.parentElement;
    if (!parent) return;
    const rect = parent.getBoundingClientRect();
    width = Math.max(1, Math.floor(rect.width));
    height = Math.max(1, Math.floor(rect.height));
    dpr = Math.min(window.devicePixelRatio || 1, 2);

    canvas.width = width * dpr;
    canvas.height = height * dpr;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

    drawFrame();
  }

  function drawFrame() {
    ctx.clearRect(0, 0, width, height);

    const shorterSide = Math.min(width, height);
    const sphereRadius = shorterSide * 0.46;
    const narrow = width < 760;
    // On narrow screens the text spans the full width: keep the sphere as a faint backdrop.
    const alphaMul = narrow ? 0.4 : 1;
    const centerX = width * (narrow ? 0.7 : 0.68);
    const centerY = height * (narrow ? 0.7 : 0.52);

    // Scale font size with sphere radius between 15px and 22px
    const fontSize = Math.round(Math.min(22, Math.max(15, sphereRadius * 0.072)));

    const pitch = rotX + currentParallaxY * 0.35;
    const yaw = rotY + currentParallaxX * 0.35;

    const cosY = Math.cos(yaw);
    const sinY = Math.sin(yaw);
    const cosX = Math.cos(pitch);
    const sinX = Math.sin(pitch);

    let rearCount = 0;
    let frontCount = 0;

    for (let i = 0; i < COUNT; i++) {
      const p = points[i];

      // Rotate around Y
      const x1 = p.x * cosY - p.z * sinY;
      const z1 = p.z * cosY + p.x * sinY;

      // Rotate around X
      const y2 = p.y * cosX - z1 * sinX;
      const z2 = z1 * cosX + p.y * sinX;

      // Depth normalize (-1..1 -> 0..1)
      const depth = (z2 + 1) * 0.5;
      const perspective = 0.78 + depth * 0.44;
      const screenX = centerX + x1 * sphereRadius * perspective;
      const screenY = centerY + y2 * sphereRadius * perspective;
      const scrim = computeScrimFactor(screenX) * alphaMul;

      p.screenX = screenX;
      p.screenY = screenY;

      if (z2 < 0) {
        // Rear hemisphere: alpha floor 0.30 up to 0.55 (light tint #F5F4F0 at ~55% alpha)
        const rearAlpha = 0.30 + (depth / 0.5) * 0.25;
        p.alpha = rearAlpha * scrim;
        rearQueue[rearCount++] = p;
      } else {
        // Front hemisphere: brand green #19E36B, alpha 0.60 up to 1.0
        const frontAlpha = 0.60 + ((depth - 0.5) / 0.5) * 0.40;
        p.alpha = Math.min(1.0, frontAlpha) * scrim;
        frontQueue[frontCount++] = p;
      }
    }

    ctx.font = '600 ' + fontSize + 'px "JetBrains Mono", ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';

    // Pass 1: Rear hemisphere glyphs (no shadow)
    ctx.shadowBlur = 0;
    ctx.shadowColor = 'transparent';
    ctx.fillStyle = REAR_COLOR;
    for (let i = 0; i < rearCount; i++) {
      const p = rearQueue[i];
      ctx.globalAlpha = p.alpha;
      ctx.fillText(p.glyph, p.screenX, p.screenY);
    }

    // Pass 2: Front hemisphere glyphs (brand green + soft glow, reset after)
    ctx.fillStyle = FRONT_COLOR;
    ctx.shadowColor = FRONT_GLOW_COLOR;
    ctx.shadowBlur = FRONT_SHADOW_BLUR;
    for (let i = 0; i < frontCount; i++) {
      const p = frontQueue[i];
      ctx.globalAlpha = p.alpha;
      ctx.fillText(p.glyph, p.screenX, p.screenY);
    }

    // Reset shadow and alpha state
    ctx.shadowBlur = 0;
    ctx.shadowColor = 'transparent';
    ctx.globalAlpha = 1;
  }

  function tick() {
    if (!isVisible || isReducedMotion) {
      rafId = null;
      return;
    }

    rotY += 0.0022;
    currentParallaxX += (targetParallaxX - currentParallaxX) * 0.06;
    currentParallaxY += (targetParallaxY - currentParallaxY) * 0.06;

    drawFrame();
    rafId = window.requestAnimationFrame(tick);
  }

  function startLoop() {
    if (isReducedMotion) {
      drawFrame();
      return;
    }
    if (!rafId && isVisible) {
      rafId = window.requestAnimationFrame(tick);
    }
  }

  function stopLoop() {
    if (rafId) {
      window.cancelAnimationFrame(rafId);
      rafId = null;
    }
  }

  // Pointer parallax (disabled in reduced motion)
  const heroFrame = canvas.parentElement;
  if (heroFrame) {
    heroFrame.addEventListener('pointermove', function (e) {
      if (isReducedMotion) return;
      const rect = heroFrame.getBoundingClientRect();
      const nx = ((e.clientX - rect.left) / rect.width) * 2 - 1;
      const ny = ((e.clientY - rect.top) / rect.height) * 2 - 1;
      targetParallaxX = nx;
      targetParallaxY = ny;
    }, { passive: true });

    heroFrame.addEventListener('pointerleave', function () {
      targetParallaxX = 0;
      targetParallaxY = 0;
    }, { passive: true });
  }

  // Pause when off-screen via IntersectionObserver
  if ('IntersectionObserver' in window) {
    const observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        isVisible = entry.isIntersecting;
        if (isVisible) {
          startLoop();
        } else {
          stopLoop();
        }
      });
    }, { threshold: 0.05 });

    observer.observe(canvas);
  }

  // Listen for OS reduced-motion changes
  reducedMotionQuery.addEventListener('change', function (e) {
    isReducedMotion = e.matches;
    if (isReducedMotion) {
      stopLoop();
      currentParallaxX = 0;
      currentParallaxY = 0;
      drawFrame();
    } else {
      startLoop();
    }
  });

  window.addEventListener('resize', resize, { passive: true });
  resize();
  startLoop();
})();
