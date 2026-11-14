---
name: customer-journey-optimizer
description: >-
  Guía paso a paso para analizar, condensar y optimizar el recorrido del cliente (Customer Journey)
  en la landing page de PaydMex. Úsala cuando se requiera evaluar fricciones, simplificar el embudo
  de conversión, reducir la carga cognitiva o rediseñar la experiencia visual del cliente y comerciante.
---

# Customer Journey Optimizer — PaydMex

Esta skill proporciona un marco de trabajo y procedimientos accionables para transformar la landing page de PaydMex en una experiencia directa, fluida y de alta conversión para clientes reales.

---

## 1. Perfiles de Cliente Real en PaydMex

En PaydMex convergen dos perfiles fundamentales a través de una sola cuenta:

| Perfil | Rol Principal | Objetivo Inmediato | Fricción Principal | Solución en Landing |
| :--- | :--- | :--- | :--- | :--- |
| **Comerciante (Negocio)** | Cobra con CoDi en su negocio (taquería, abarrotes, ropa, servicios) | Dejar de perder 3.5%-4.6% en comisiones bancarias y no depender de terminales caras | Desconfianza de si el dinero cae de inmediato o si es difícil de configurar | Comparativa 0% comisión, simulador en vivo de cobro POS en 3 pasos, demostración de dinero directo a cuenta |
| **Comprador (Cliente Final)** | Paga en el local escaneando QR CoDi con su app bancaria | Pagar rápido sin efectivo ni tarjeta física, sin registros complicados | Miedo a tener que instalar otra app o ingresar datos sensibles | Claridad de que paga con la app de su propio banco (BBVA, Banorte, Santander, etc.) y seguimiento en vivo del pedido |

---

## 2. Metodología de Condensación de Flujos

Para cualquier sección o flujo del recorrido, aplicar el principio de los 3 tiempos:

```text
[1. Haces]        → Acción del usuario (escribes monto / abres app de tu banco)
[2. Pasa]         → Respuesta del sistema (genera QR CoDi / webhook confirma pago)
[3. Recibes]      → Resultado tangible (dinero en cuenta al 100% / "¡Cobrado! +$85.00")
```

### Reglas de Poda Cognitiva:
1. **Regla de los 5 segundos**: El usuario debe entender qué hace PaydMex antes del primer scroll.
2. **Eliminar redundancia narrativa**: Si un mock animado ya muestra cómo se genera el QR, no repetir tres párrafos describiéndolo.
3. **Microinteracciones en lugar de texto estático**: Mostrar el flujo activo mediante toggles segmentados, tabs sincronizados o visualizadores interactivos.
4. **Claridad del CTA**: Cada bloque de decisión debe tener una llamada a la acción inequívoca ("Probar la app" o "Ver cómo funciona").

---

## 3. Procedimiento de Optimización Paso a Paso

### Paso 1: Mapeo y Detección de Fricción
- Analizar el orden de las secciones en `apps/landing/index.html`.
- Evaluar si el usuario encuentra antes el valor (0% comisión, facilidad CoDi) o explicaciones abstractas.
- Medir la distancia en píxeles y scroll entre el Hero y la primera interacción real.

### Paso 2: Condensación del Recorrido del Cliente Final
- Verificar que el flujo del **comprador** no quede escondido como una pestaña secundaria.
- Representar visualmente el viaje del comprador:
  1. El cliente pide en mostrador.
  2. Abre la app de su banco y escanea el QR CoDi de PaydMex.
  3. Autoriza con su huella/PIN en su banco.
  4. Ambas partes ven la confirmación instantánea sin comisiones.

### Paso 3: Optimización del Recorrido del Comerciante
- Reforzar el ahorro real frente a competidores (Clip, Mercado Pago, Zettle).
- Destacar que no se requiere hardware adicional (solo un celular o tablet).
- Integrar la asistencia de IA como un facilitador de inventario y pedidos, no como un obstáculo.

### Paso 4: Validación y Medición
- Verificar accesibilidad (WCAG 2.1 AA), contraste y etiquetas semánticas.
- Probar en viewport móvil (375px a 412px) asegurando que el contenido clave no requiera scroll excesivo.
- Confirmar que los tokens CSS de `apps/landing/css/tokens.css` se respeten rigurosamente.
