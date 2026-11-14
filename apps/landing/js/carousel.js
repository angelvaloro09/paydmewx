/**
 * PaydMex Landing — Categories Carousel (B1 / T23a)
 */
(function () {
  'use strict';

  const AUTOPLAY_MS = 5000;
  const carousel = document.querySelector('[data-carousel]');
  if (!carousel) return;

  const track = carousel.querySelector('[data-carousel-track]');
  const slides = Array.from(carousel.querySelectorAll('[data-carousel-slide]'));
  const prevBtn = carousel.querySelector('[data-carousel-prev]');
  const nextBtn = carousel.querySelector('[data-carousel-next]');
  const toggleBtn = carousel.querySelector('[data-carousel-toggle]');
  const toggleUse = toggleBtn ? toggleBtn.querySelector('use') : null;
  const toggleLabel = toggleBtn ? toggleBtn.querySelector('[data-carousel-toggle-label]') : null;
  const dots = Array.from(carousel.querySelectorAll('[data-carousel-dot]'));
  const liveRegion = carousel.querySelector('[data-carousel-live]');

  if (!track || slides.length === 0) return;

  const motionQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
  let isReducedMotion = motionQuery.matches;
  let userPaused = isReducedMotion;
  let isHovered = false;
  let isFocusWithin = false;
  let activeIndex = 0;
  let timerId = null;

  function isPaused() {
    return Boolean(userPaused || isReducedMotion);
  }

  function getSlideOffset(idx) {
    const first = slides[0];
    const target = slides[idx];
    return first && target ? target.offsetLeft - first.offsetLeft : 0;
  }

  function updateActiveUi(idx) {
    activeIndex = idx;
    dots.forEach(function (dot, i) {
      if (i === idx) {
        dot.setAttribute('aria-current', 'true');
        dot.classList.add('is-active');
      } else {
        dot.removeAttribute('aria-current');
        dot.classList.remove('is-active');
      }
    });
  }

  function updateToggleUi() {
    if (!toggleBtn) return;
    const paused = isPaused();
    toggleBtn.setAttribute('aria-pressed', paused ? 'true' : 'false');
    toggleBtn.setAttribute(
      'aria-label',
      paused ? 'Reanudar carrusel automático' : 'Pausar carrusel automático'
    );
    if (toggleUse) toggleUse.setAttribute('href', paused ? '#ph-play' : '#ph-pause');
    if (toggleLabel) toggleLabel.textContent = paused ? 'Reanudar' : 'Pausar';
  }

  function announceSlide(idx, polite) {
    if (!liveRegion) return;
    liveRegion.setAttribute('aria-live', polite ? 'polite' : 'off');
    if (!polite) {
      liveRegion.textContent = '';
      return;
    }
    const heading = slides[idx] ? slides[idx].querySelector('h3') : null;
    const title = heading ? heading.textContent.trim() : '';
    liveRegion.textContent = 'Tarjeta ' + (idx + 1) + ' de ' + slides.length + (title ? ': ' + title : '');
  }

  function findClosestSlideIndex() {
    const current = track.scrollLeft;
    let best = 0;
    let minDiff = Infinity;
    for (let i = 0; i < slides.length; i++) {
      const diff = Math.abs(getSlideOffset(i) - current);
      if (diff < minDiff) {
        minDiff = diff;
        best = i;
      }
    }
    return best;
  }

  function clearAutoplayTimer() {
    if (timerId !== null) {
      window.clearInterval(timerId);
      timerId = null;
    }
  }

  function cancelInFlightScroll() {
    track.style.scrollSnapType = 'none';
    track.style.scrollBehavior = 'auto';
    track.scrollTo({ left: track.scrollLeft, behavior: 'auto' });
    updateActiveUi(findClosestSlideIndex());
  }

  function goToSlide(idx, opts) {
    const options = opts || {};
    if (options.fromAutoplay && isPaused()) return;

    const count = slides.length;
    const normalized = ((idx % count) + count) % count;
    const instant = Boolean(options.instant || isReducedMotion);

    track.style.scrollSnapType = '';
    track.style.scrollBehavior = '';

    announceSlide(normalized, Boolean(options.announce));
    updateActiveUi(normalized);
    track.scrollTo({
      left: getSlideOffset(normalized),
      behavior: instant ? 'auto' : 'smooth',
    });
  }

  let scrollRaf = 0;
  track.addEventListener(
    'scroll',
    function () {
      if (scrollRaf) return;
      scrollRaf = window.requestAnimationFrame(function () {
        scrollRaf = 0;
        const closest = findClosestSlideIndex();
        if (closest !== activeIndex) updateActiveUi(closest);
      });
    },
    { passive: true }
  );

  // Pointer drag with inertia-free snapping
  let isDragging = false;
  let startX = 0;
  let startScroll = 0;
  let startSlide = 0;

  track.addEventListener('pointerdown', function (e) {
    if (e.pointerType !== 'mouse' || e.button !== 0) return;
    isDragging = true;
    startX = e.clientX;
    startScroll = track.scrollLeft;
    startSlide = activeIndex;
    track.classList.add('is-dragging');
    if (track.setPointerCapture) {
      try {
        track.setPointerCapture(e.pointerId);
      } catch (_) {}
    }
  });

  track.addEventListener('pointermove', function (e) {
    if (!isDragging) return;
    track.scrollLeft = startScroll - (e.clientX - startX);
  });

  function finishDrag(e) {
    if (!isDragging) return;
    isDragging = false;
    track.classList.remove('is-dragging');
    if (track.releasePointerCapture && e && e.pointerId !== undefined) {
      try {
        track.releasePointerCapture(e.pointerId);
      } catch (_) {}
    }
    const dx = e ? e.clientX - startX : 0;
    let target = findClosestSlideIndex();
    if (Math.abs(dx) > 48 && target === startSlide) {
      target = dx < 0 ? startSlide + 1 : startSlide - 1;
    }
    goToSlide(target, { announce: true });
    restartAutoplay();
  }

  track.addEventListener('pointerup', finishDrag);
  track.addEventListener('pointercancel', finishDrag);

  track.addEventListener('keydown', function (e) {
    if (e.key === 'ArrowRight') {
      e.preventDefault();
      goToSlide(activeIndex + 1, { announce: true });
      restartAutoplay();
    } else if (e.key === 'ArrowLeft') {
      e.preventDefault();
      goToSlide(activeIndex - 1, { announce: true });
      restartAutoplay();
    } else if (e.key === 'Home') {
      e.preventDefault();
      goToSlide(0, { announce: true });
      restartAutoplay();
    } else if (e.key === 'End') {
      e.preventDefault();
      goToSlide(slides.length - 1, { announce: true });
      restartAutoplay();
    }
  });

  if (prevBtn) {
    prevBtn.addEventListener('click', function () {
      goToSlide(activeIndex - 1, { announce: true });
      restartAutoplay();
    });
  }

  if (nextBtn) {
    nextBtn.addEventListener('click', function () {
      goToSlide(activeIndex + 1, { announce: true });
      restartAutoplay();
    });
  }

  dots.forEach(function (dot, i) {
    dot.addEventListener('click', function () {
      goToSlide(i, { announce: true });
      restartAutoplay();
    });
  });

  if (toggleBtn) {
    toggleBtn.addEventListener('click', function () {
      userPaused = !userPaused;
      if (isReducedMotion && !userPaused) isReducedMotion = false;
      updateToggleUi();
      if (isPaused()) {
        clearAutoplayTimer();
        cancelInFlightScroll();
      } else {
        track.style.scrollSnapType = '';
        track.style.scrollBehavior = '';
        restartAutoplay();
      }
    });
  }

  track.addEventListener('pointerenter', function () {
    isHovered = true;
  });
  track.addEventListener('pointerleave', function () {
    isHovered = false;
  });
  track.addEventListener('focusin', function () {
    isFocusWithin = true;
  });
  track.addEventListener('focusout', function (e) {
    if (!track.contains(e.relatedTarget)) isFocusWithin = false;
  });

  document.addEventListener('visibilitychange', function () {
    if (document.hidden) {
      clearAutoplayTimer();
    } else {
      restartAutoplay();
    }
  });

  if (typeof motionQuery.addEventListener === 'function') {
    motionQuery.addEventListener('change', function (e) {
      isReducedMotion = e.matches;
      if (isReducedMotion) {
        userPaused = true;
        clearAutoplayTimer();
        cancelInFlightScroll();
      }
      updateToggleUi();
      restartAutoplay();
    });
  }

  function restartAutoplay() {
    clearAutoplayTimer();
    if (isPaused()) return;
    timerId = window.setInterval(function () {
      if (!isPaused() && !isHovered && !isFocusWithin && !document.hidden) {
        goToSlide(activeIndex + 1, { announce: false, fromAutoplay: true });
      }
    }, AUTOPLAY_MS);
  }

  updateActiveUi(0);
  updateToggleUi();
  restartAutoplay();
})();
