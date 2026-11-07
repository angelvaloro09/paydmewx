# PaydMex — Design System v1

Brand: **PaydMex**. Spanish (MX), informal "tú". Feel: confident, fast, warm, a little playful — fintech that a taco stall and a department store can both use.
Principle: **big type, flat surfaces, one loud accent, motion that confirms money moved.**

## What we took from each reference (measured from the live sites)
| Source | Measured | We use it for |
|---|---|---|
| Cash App Design | Black/white + one green `#00d533`; display type at 8vw–24vw; no radii/shadows; easing `cubic-bezier(.215,.61,.355,1)` at .3s/.6s; frame-sequence loader; plain legal-honest voice | Oversized numbers & headlines, flat tonal surfaces, entrance easing, splash loader, honest microcopy |
| v0 Optimus | Warm paper bg (~`#FAF9F6`), near-black ink, Instrument Sans light at 160px, mono micro-labels with leading hairline, black pill buttons, hairline grid, glyph-particle sphere, ease `(.4,0,0,.2,1)` 150ms–1s | Landing hero, paper theme, mono eyebrow labels, pill CTAs, particle hero (glyphs `$ ¢ ₱`) |
| Duxica | Plus Jakarta Sans, ink `#16151A`, radius scale 6/8/12/16/24/pill, stats strip, 3-tier pricing with "Popular", testimonials, ease `(.455,.03,.515,.955)` .2s | Radius scale, KPI/stat strip (merchant dashboard + landing), pricing section |
| Time to Refokus | Dark rounded frame inset in a light lavender page, Satoshi, giant uppercase hero, glow orb, "push to start" gate, pill segmented toggle, AI guide that greets + suggests prompt chips, casual voice | AI assistant (orb + greeting + suggested chips), Cliente/Negocio segmented pill toggle, dark hero frame on landing, casual copy |
| Luma | Dark UI `#151515`, surfaces `rgba(255,255,255,.04/.08)`, radii 8/16/24/100, soft layered shadow only on floating items, left date-rail timeline list, LIVE badge, green pill CTA, avatar stacks, `.3s (.4,0,.2,1)` | Dark POS theme, orders timeline with time rail, status badges, tonal cards |

## Color tokens
| Token | Light | Dark | Use |
|---|---|---|---|
| `bg` | `#FAF9F6` | `#0B0B0C` | app/page background |
| `surface` | `#FFFFFF` | `rgba(255,255,255,.04)` over bg | cards |
| `surface2` | `#F1EFEA` | `rgba(255,255,255,.08)` | raised/selected |
| `ink` | `#0A0A0A` | `#F5F4F0` | primary text |
| `inkMuted` | `#5B5B57` | `#A3A39E` | secondary text (>=4.5:1) |
| `line` | `rgba(10,10,10,.10)` | `rgba(255,255,255,.10)` | hairlines |
| `brand` (Verde Pago) | `#00C853` | `#19E36B` | primary actions, success, paid |
| `onBrand` | `#0A0A0A` | `#0A0A0A` | text on brand (never white on green) |
| `cempasuchil` | `#FF8A1F` | `#FFA04D` | preparing / attention |
| `rosa` (Rosa Mexicano) | `#E4007C` | `#FF3D9A` | AI accent (orb, sparkle) — gradient `rosa → cempasuchil` |
| `codi` | `#2F6BFF` | `#6C9BFF` | QR / CoDi info |
| `danger` | `#D92D20` | `#FF6B5E` | errors, cancelled |
Green text on white fails contrast: use `brand` as a fill only, or `#00763A` for text on light.
Status is always **color + icon + label** (never color alone).

## Typography
- **Instrument Sans** (UI + display; weights 400/500/600, display uses 400 for the big-light look). Fallback system sans.
- **JetBrains Mono** for eyebrow labels (`UPPERCASE`, 12px, +0.08em, preceded by a 24px hairline) and tabular amounts.
- Scale (mobile / web): display 56/120, h1 40/72, h2 28/48, h3 20/28, body 16, small 14, micro 12. Line-height display 1.0, body 1.5. Money always tabular figures.
- Must honor system text scale up to 200% without clipping.

## Shape, spacing, elevation
- Radius: `sm 8`, `md 12`, `lg 16`, `xl 24` (cards, sheets), `pill 999` (buttons, chips, toggles, inputs on web search). Inputs `16`.
- Spacing unit 4: 4, 8, 12, 16, 24, 32, 48, 64.
- Flat by default (tonal fills + hairline). Shadow only for floating layers: `0 8px 24px rgba(0,0,0,.18), 0 2px 6px rgba(0,0,0,.12)`.
- Touch targets >= 48dp. Max content width web 1120; side rail >= 900px, bottom bar below.

## Motion tokens
| Token | Value | Use |
|---|---|---|
| `easeOut` | `cubic-bezier(.215,.61,.355,1)` | entrances (Cash) |
| `easeStd` | `cubic-bezier(.4,0,.2,1)` | state changes (Luma/Optimus) |
| `fast / base / slow / hero` | 150 / 300 / 600 / 1000 ms | |
Signature moments (implement these, skip the rest):
1. **Splash**: PaydMex mark pulses in a ring (frame/tween loader, <= 1.2s, skippable).
2. **Giant-type reveal**: hero lines rise 24px + fade, 60ms stagger, `easeOut` 600ms.
3. **Cobro exitoso**: QR card cross-fades to a check inside an expanding ring in `brand`, amount counts up, light haptic. The most important animation in the product.
4. **Stats strip**: numbers count up once on first view (Duxica).
5. **AI orb**: soft glow breathing 3s loop (rosa→cempasuchil); greeting + 3 suggested prompt chips (Refokus). Listening state = ring pulse.
6. **Segmented pill toggle** Cliente | Negocio slides its thumb 300ms (`easeStd`).
7. **Orders timeline**: left time rail with dot, LIVE/Preparando badges (Luma).
8. **Landing hero**: glyph-particle sphere (`$ ¢ ₱`, canvas, ~600 glyphs, slow rotation, pointer parallax) inside a dark rounded frame on the paper page (Optimus + Refokus).
Reduced motion (OS setting): no parallax/particles/count-up; transitions become <=150ms opacity only; keep the success check (static).

## Components (build once, reuse)
`PxButton` (primary brand pill / secondary outline / ghost; min height 52; loading state), `PxCard`, `PxChip` (filter + status), `PxBadge` (LIVE, status), `PxField` (label above, helper/error below), `PxSegmented` (pill toggle), `PxStat` (big number + mono label), `PxListTile` (timeline row), `PxQrCard`, `PxEmptyState` (illustration-free: big glyph + 1 line + CTA), `PxSheet` (bottom sheet / side panel), `PxAiOrb`, `PxNumpad` (POS amount entry, large keys), `PxToast`.

## Voice (es-MX)
Short, warm, direct. "Cobra en segundos." "¡Cobrado! +$85.00". Errors say what happened and what to do: "No pudimos generar el QR. Intenta de nuevo." Never jargon ("CLABE", "CoDi") without a one-line explanation the first time.

## Accessibility (non-negotiable)
Contrast >= 4.5:1 text / 3:1 UI; labels on every control; focus order and visible focus ring (2px `brand` + 2px offset); screen-reader announcements for payment state changes ("Pago recibido por 85 pesos"); text scale to 200%; reduce-motion respected; high-contrast theme option; voice input on the AI assistant; large-key numpad; no information by color alone; haptics optional.

## Tokens delivery
- Flutter: `apps/app/lib/core/theme/{tokens.dart,theme.dart,motion.dart}` — single source; `ColorScheme` for light+dark from the table.
- Landing: CSS custom properties in `apps/landing/css/tokens.css` using the same names/values.
