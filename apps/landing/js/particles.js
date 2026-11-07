/**
 * PaydMex — Hero Glyph-Particle Sphere (js/particles.js)
 * Renders ~600 currency/math glyphs ($ ¢ ₱ +) distributed on a Fibonacci sphere.
 * Features: slow rotation, pointer parallax, DPR capped at 2,
 * IntersectionObserver off-screen pause, single static frame when prefers-reduced-motion: reduce.
 */
(function () {
  'use strict';

  const canvas = document.getElementById('hero-particles');
  if (!canvas) return;

  const ctx = canvas.getContext('2d');
  if (!ctx) return;

  const GLYPHS = ['$', '¢', '₱', '+'];
  const COUNT = 600;
  const GOLDEN_ANGLE = Math.PI * (3 - Math.sqrt(5));

  const reducedMotionQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
  let isReducedMotion = reducedMotionQuery.matches;

  // Build Fibonacci sphere points
  const points = [];
  for (let i = 0; i < COUNT; i++) {
    const y = 1 - (i / (COUNT - 1)) * 2;
    const radiusAtY = Math.sqrt(1 - y * y);
    const theta = GOLDEN_ANGLE * i;
    points.push({
      x: Math.cos(theta) * radiusAtY,
      y: y,
      z: Math.sin(theta) * radiusAtY,
      glyph: GLYPHS[i % GLYPHS.length],
      isBrand: i % 19 === 0
    });
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

  function resize() {
    const rect = canvas.parentElement.getBoundingClientRect();
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

    const sphereRadius = Math.min(width, height) * (width >= 760 ? 0.42 : 0.36);
    const centerX = width >= 760 ? width * 0.72 : width * 0.58;
    const centerY = height * 0.52;

    const pitch = rotX + currentParallaxY * 0.35;
    const yaw = rotY + currentParallaxX * 0.35;

    const cosY = Math.cos(yaw);
    const sinY = Math.sin(yaw);
    const cosX = Math.cos(pitch);
    const sinX = Math.sin(pitch);

    ctx.font = '500 13px "JetBrains Mono", monospace';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';

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
      if (depth < 0.08) continue;

      const perspective = 0.78 + depth * 0.44;
      const screenX = centerX + x1 * sphereRadius * perspective;
      const screenY = centerY + y2 * sphereRadius * perspective;

      const alpha = Math.min(0.88, Math.max(0.08, depth * depth * 0.85));

      if (p.isBrand) {
        ctx.fillStyle = 'rgba(25, 227, 107, ' + alpha.toFixed(2) + ')';
      } else {
        ctx.fillStyle = 'rgba(245, 244, 240, ' + (alpha * 0.68).toFixed(2) + ')';
      }

      ctx.fillText(p.glyph, screenX, screenY);
    }
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
