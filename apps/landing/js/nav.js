/**
 * PaydMex — Floating Glass Pill Navigation (js/nav.js)
 * Handles:
 * 1. Scrollspy via IntersectionObserver on linked sections (aria-current="true")
 * 2. Sliding active pill positioned via transform + width (300ms --easeStd; instant in reduced motion)
 * 3. Accessible mobile disclosure (<760px): aria-expanded, Escape closes & returns focus
 */
(function () {
  'use strict';

  const header = document.getElementById('site-header');
  const navToggle = document.getElementById('nav-toggle');
  const navMenu = document.getElementById('nav-menu');
  const activePill = document.getElementById('nav-active-pill');
  const navLinks = Array.from(document.querySelectorAll('.nav-list .nav-link[href^="#"]'));

  if (!header) return;

  const reducedMotionQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
  const mobileQuery = window.matchMedia('(max-width: 759px)');

  // 1. Mobile menu disclosure
  function setMenuOpen(open) {
    if (!navToggle || !navMenu) return;
    navToggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    navToggle.setAttribute('aria-label', open ? 'Cerrar menú de navegación' : 'Abrir menú de navegación');
    navMenu.classList.toggle('is-open', open);
  }

  if (navToggle && navMenu) {
    navToggle.addEventListener('click', function () {
      const expanded = navToggle.getAttribute('aria-expanded') === 'true';
      setMenuOpen(!expanded);
    });

    navMenu.querySelectorAll('a').forEach(function (link) {
      link.addEventListener('click', function () {
        setMenuOpen(false);
      });
    });

    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && navToggle.getAttribute('aria-expanded') === 'true') {
        setMenuOpen(false);
        navToggle.focus();
      }
    });

    document.addEventListener('click', function (e) {
      if (
        navToggle.getAttribute('aria-expanded') === 'true' &&
        !header.contains(e.target)
      ) {
        setMenuOpen(false);
      }
    });

    mobileQuery.addEventListener('change', function (e) {
      if (!e.matches) {
        setMenuOpen(false);
      }
      syncActivePill();
    });
  }

  // 2. Sliding active pill & aria-current management
  // No active link while the hero (no linked section) is on screen.
  let currentLink = null;

  function clearActiveLink() {
    currentLink = null;
    for (let i = 0; i < navLinks.length; i++) {
      navLinks[i].removeAttribute('aria-current');
    }
    syncActivePill();
  }

  function syncActivePill() {
    if (!activePill || !currentLink || mobileQuery.matches) {
      if (activePill) {
        activePill.classList.remove('is-visible');
      }
      return;
    }

    const wrap = activePill.parentElement;
    if (!wrap) return;

    const wrapRect = wrap.getBoundingClientRect();
    const linkRect = currentLink.getBoundingClientRect();
    if (linkRect.width <= 0) return;

    const offsetLeft = linkRect.left - wrapRect.left;
    activePill.style.width = linkRect.width.toFixed(1) + 'px';
    activePill.style.transform = 'translateX(' + offsetLeft.toFixed(1) + 'px)';
    activePill.classList.add('is-visible');
  }

  function setActiveLink(targetLink) {
    if (!targetLink) return;
    currentLink = targetLink;
    for (let i = 0; i < navLinks.length; i++) {
      const link = navLinks[i];
      if (link === targetLink) {
        link.setAttribute('aria-current', 'true');
      } else {
        link.removeAttribute('aria-current');
      }
    }
    syncActivePill();
  }

  // Wire click listeners so clicking a nav link immediately activates it
  const sectionToLink = new Map();
  const sections = [];

  for (let i = 0; i < navLinks.length; i++) {
    const link = navLinks[i];
    const hash = link.getAttribute('href');
    if (hash && hash.length > 1) {
      const sec = document.getElementById(hash.slice(1));
      if (sec) {
        sectionToLink.set(sec, link);
        sections.push(sec);
      }
    }
    link.addEventListener('click', function () {
      setActiveLink(link);
    });
  }

  // 3. Scrollspy via IntersectionObserver
  if (sections.length > 0 && 'IntersectionObserver' in window) {
    const intersectingSections = new Set();

    const spyObserver = new IntersectionObserver(
      function (entries) {
        for (let i = 0; i < entries.length; i++) {
          const entry = entries[i];
          if (entry.isIntersecting) {
            intersectingSections.add(entry.target);
          } else {
            intersectingSections.delete(entry.target);
          }
        }

        if (intersectingSections.size === 0) {
          clearActiveLink();
          return;
        }

        // Pick the intersecting section whose top is closest to the upper reading band
        const targetLine = (window.innerHeight || 800) * 0.28;
        let bestSection = null;
        let bestDist = Infinity;

        intersectingSections.forEach(function (sec) {
          const rect = sec.getBoundingClientRect();
          const dist = Math.abs(rect.top - targetLine);
          if (dist < bestDist) {
            bestDist = dist;
            bestSection = sec;
          }
        });

        if (bestSection && sectionToLink.has(bestSection)) {
          setActiveLink(sectionToLink.get(bestSection));
        }
      },
      {
        rootMargin: '-18% 0px -48% 0px',
        threshold: [0, 0.15, 0.4]
      }
    );

    for (let i = 0; i < sections.length; i++) {
      spyObserver.observe(sections[i]);
    }
  }

  window.addEventListener('resize', syncActivePill, { passive: true });
  reducedMotionQuery.addEventListener('change', syncActivePill);

  if (document.fonts && document.fonts.ready) {
    document.fonts.ready.then(syncActivePill);
  }
})();
