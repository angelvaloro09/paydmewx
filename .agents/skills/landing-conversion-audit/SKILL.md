---
name: landing-conversion-audit
description: >-
  Auditoría técnica y de experiencia de usuario para la landing page de PaydMex.
  Úsala para verificar cumplimiento del sistema de diseño, accesibilidad WCAG 2.1 AA,
  responsividad móvil, performance y ausencia de elementos bloqueantes o emojis no permitidos.
---

# Landing Conversion & UX Audit — PaydMex

Esta skill establece el proceso de verificación técnica, accesibilidad y diseño para garantizar que cualquier mejora en la landing page mantenga los más altos estándares de calidad y fidelidad de marca.

---

## 1. Verificación de Tokens de Diseño

Comprobar que todas las clases y estilos implementados utilicen los tokens oficiales definidos en `docs/DESIGN_SYSTEM.md` y `apps/landing/css/tokens.css`:

- [ ] **Colores**:
  - Fondo papel: `var(--bg)` (`#FAF9F6`) / Fondo oscuro: `var(--bg-dark)` (`#0B0B0C`).
  - Marca: `var(--brand)` (`#00C853`). **Prohibido texto blanco sobre verde.** Texto sobre marca debe ser `var(--on-brand)` (`#0A0A0A`).
  - Textos: `var(--ink)` (`#0A0A0A`), `var(--ink-muted)` (`#5B5B57`).
  - Acentos de estado: `var(--codi)` (`#2F6BFF`), `var(--cempasuchil)` (`#FF8A1F`), `var(--rosa)` (`#E4007C`).
- [ ] **Tipografía**:
  - `Instrument Sans` como fuente principal.
  - `JetBrains Mono` o fuente monoespaciada para eyebrows en mayúsculas (`UPPERCASE`, tracking +0.08em) y cifras tabulares.
- [ ] **Bordes y Radios**:
  - Escala de radios: `8px`, `12px`, `16px`, `24px` y `pill (999px)`.
  - Botones principales en estilo `pill`.

---

## 2. Checklist de Accesibilidad (WCAG 2.1 AA)

- [ ] **Contraste de Color**:
  - Mínimo 4.5:1 para texto normal y 3:1 para controles y gráficos interactivos.
  - El estado nunca se comunica únicamente por color: siempre **color + icono + texto**.
- [ ] **Navegación por Teclado**:
  - Enlaces y botones interactivos deben ser alcanzables por `Tab`.
  - Indicador de foco visible (`2px brand + 2px offset`).
  - Enlace de salto inicial (`.skip-link` a `#main-content`).
- [ ] **Lectores de Pantalla**:
  - Iconos decorativos con `aria-hidden="true"`.
  - Botones con `aria-label` descriptivos.
  - Anuncios dinámicos en cambios de estado importantes.
- [ ] **Movimiento Reducido**:
  - La media query `@media (prefers-reduced-motion: reduce)` debe desactivar partículas en canvas, transiciones complejas o auto-scrolling.

---

## 3. Scripts de Verificación del Repositorio

El proyecto incluye scripts de verificación en Node.js que deben ejecutarse ante cambios:

1. **Verificación de emojis**:
   ```bash
   node scripts/check-no-emoji.mjs
   ```
   *PaydMex utiliza iconos Phosphor en SVG (`assets/icons/sprite.svg`), nunca emojis en la interfaz ni en el copy.*

2. **Compilación de sprite de iconos (si se agregan nuevos iconos SVG)**:
   ```bash
   node scripts/build-icon-sprite.mjs
   ```

---

## 4. Pruebas de Responsividad

Validar la jerarquía visual en los siguientes anchos de pantalla:
1. **Móvil pequeño (360px - 390px)**: Teclados, tarjetas y botones pill deben mantener tamaño táctil >= 48dp sin desbordamientos horizontales.
2. **Móvil estándar (412px - 430px)**: Espaciado armónico, textos legibles sin truncamiento involuntario.
3. **Escritorio (1024px - 1440px)**: Ancho máximo de contenido contenido en 1120px, centrado y con márgenes limpios.
