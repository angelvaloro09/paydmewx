# Reglas de Proyecto: PaydMex Landing Page — Optimización del Flujo del Cliente

Este espacio de trabajo está dedicado a la mejora, condensación y optimización de la landing page de **PaydMex** (`apps/landing`), enfocándose en el flujo de recorrido de un cliente real y la adopción del producto.

---

## 1. Principios de Recorrido del Cliente (Customer Journey)

1. **Condensación y Claridad Radical**:
   - Cada sección debe responder rápidamente a una de tres preguntas del usuario: *¿Qué es?*, *¿Cómo funciona para mí?*, y *¿Por qué me conviene frente a terminales tradicionales?*.
   - Reducir la fricción cognitiva: sustituir bloques extensos de texto por secuencias visuales claras, microinteracciones o pasos directos (*Haces → Pasa → Recibes*).
   - El cliente real (tanto el comprador que paga con CoDi como el comerciante que cobra) debe entender el valor en menos de 5 segundos de scroll.

2. **Doble Perspectiva Equilibrada**:
   - **Comerciante (Negocio)**: 0% comisión por CoDi, sin terminal física, cobro en segundos, inventario automático y asistente IA.
   - **Comprador (Cliente final)**: Pago transparente escaneando QR desde la app de su propio banco (BBVA, Banorte, Santander, etc.), sin descargar apps extrañas, seguimiento de pedido en tiempo real.
   - La landing debe comunicar de forma fluida cómo ambos lados se conectan en una sola experiencia.

3. **Demostración Práctica sobre Explicación Teórica**:
   - Priorizar simuladores interactivos o visuales del cobro y pago (monto → QR CoDi → confirmación de cobro "¡Cobrado! +$85.00").
   - Las métricas clave (0% comisión, dinero inmediato a tu cuenta, 0 intermediarios) deben destacar visualmente.

---

## 2. Sistema de Diseño y Tokens (`docs/DESIGN_SYSTEM.md`)

- **Colores Oficiales**:
  - `bg`: `#FAF9F6` (modo claro papel), `#0B0B0C` (modo oscuro).
  - `brand` (Verde Pago): `#00C853` (fondo/acento principal). *Texto sobre verde siempre debe ser `#0A0A0A`, nunca blanco.*
  - `ink`: `#0A0A0A` (texto principal), `inkMuted`: `#5B5B57` (contraste >= 4.5:1).
  - `cempasuchil`: `#FF8A1F` (pedidos en preparación / atención).
  - `rosa`: `#E4007C` (asistente de IA y orbe).
  - `codi`: `#2F6BFF` (elementos y badges CoDi).
- **Tipografía**:
  - `Instrument Sans` para display y cuerpo de texto.
  - `JetBrains Mono` o monospace para etiquetas eyebrow (`UPPERCASE`, tracking amplio, línea prefijo) y montos tabulares.
- **Formas y Espaciado**:
  - Radios: `8px` (sm), `12px` (md), `16px` (lg), `24px` (xl/tarjetas), `pill 999px` (botones y toggles).
  - Objetivos táctiles mínimos: `48 x 48 dp`.
  - Enfoque visual visible: anillo de 2px `brand` con 2px de separación para accesibilidad de teclado.

---

## 3. Tono y Voz (es-MX)

- Directo, cálido, seguro, informal ("tú").
- Lenguaje coloquial pero profesional para comerciantes de la CDMX (desde taquerías y tienditas hasta tiendas formales).
- Nunca usar tecnicismos bancarios ("CLABE", "CoDi", "webhook") sin una breve explicación en lenguaje llano la primera vez.

---

## 4. Accesibilidad y Rendimiento

- Cumplimiento estricto de WCAG 2.1 AA (contraste >= 4.5:1 para texto normal, 3:1 para UI grande).
- Soporte total para `prefers-reduced-motion` (desactivar partículas complejas, contadores automáticos acelerados y parallax).
- Mantener la landing ligera: sin dependencias pesadas de frameworks; vanilla JS modular y CSS estructurado por componentes.
- Semántica HTML estricta: landmarks `<header>`, `<main>`, `<section>`, headings estructurados (`h1` único, `h2`, `h3` sin saltos), atributos `aria-*` adecuados.

---

## 5. Control de Versiones y Buenas Prácticas

- Mantener commits limpios y atómicos con mensajes en formato convencional: `feat:`, `fix:`, `refactor:`, `style:`, `docs:`.
- Probar cambios visuales de manera responsiva (móvil 360-412px, tablet 768px, escritorio 1024-1440px).
