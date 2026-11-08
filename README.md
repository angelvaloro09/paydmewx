# PaydMex

Punto de venta, cobros CoDi, inventario y asistente de IA para comercios de la CDMX, desde el puesto de tacos hasta la tienda departamental. Hecho para el DevDay Exchange Community Hackathon CDMX sobre [pey](https://docs.pey.mx) (CoDi, Banxico).

Una sola cuenta sirve como cliente, como negocio o como ambos: "convertirte en negocio" no requiere otra cuenta.

## Qué hace

- **Cobrar en segundos (modo Negocio):** teclado numérico grande, orden de venta, QR CoDi en vivo, espera de confirmación y animación de cobro exitoso con anuncio para lector de pantalla.
- **Inventario:** productos, precios, existencias, ajustes con motivo y alertas de stock bajo.
- **Pedidos:** línea de tiempo en vivo para el negocio y para el cliente. Negocios con tiempo de elaboración pasan por preparando y listo.
- **Comprar (modo Cliente):** descubrir negocios por categoría, armar un pedido y pagarlo escaneando un QR CoDi.
- **Asistente de IA:** en lenguaje natural registra ventas, ajusta existencias, consulta inventario y resume ventas. El asistente nunca cobra: solo crea órdenes pendientes que el dueño confirma.
- **Accesibilidad desde el inicio:** etiquetas semánticas, objetivos táctiles de 48 dp, contraste de 4.5:1, escala de texto del sistema, movimiento reducido y teclas grandes.

## Cómo funciona el pago

1. La app crea una orden y pide el QR al API (`POST /orders/:id/pay`).
2. El API genera el QR CoDi con pey y la app lo dibuja localmente.
3. El pagador paga desde su app bancaria.
4. pey avisa al API con un webhook firmado (Standard Webhooks). El API verifica la firma sobre el cuerpo crudo, ignora repeticiones, marca la orden como pagada y descuenta existencias en la misma transacción.
5. La app, que consulta la orden cada 2 s, muestra "Cobrado".

Los montos son enteros en centavos. Solo se convierten a pesos en la frontera con pey. La llave de pey vive únicamente en el servidor.

## Estructura

```
apps/api      Node 22, TypeScript, Fastify, Zod, Drizzle + libSQL/Turso, Vitest
apps/app      Flutter (web, Android, iOS), Riverpod, go_router
apps/landing  sitio estático (HTML, CSS, JS)
docs/         arquitectura, contrato del API, sistema de diseño, despliegue
```

Más detalle en `docs/ARCHITECTURE.md`, `docs/API_CONTRACT.md` y `docs/DESIGN_SYSTEM.md`.

## Correr en local

Requisitos: Node 22 y Flutter 3.47.

```
cp .env.example .env        # llena tus propios valores
cd apps/api && npm ci && npm run dev          # API en http://localhost:8787
cd apps/app && flutter pub get && flutter run -d chrome
```

Variables del API (ver `.env.example`): `DATABASE_URL` y `DATABASE_AUTH_TOKEN` (archivo local o Turso), `JWT_SECRET` (mínimo 32 caracteres), `PEY_API_KEY`, `PEY_WEBHOOK_SECRET`, `PEY_TEST_AMOUNT_OVERRIDE` y `LLM_BASE_URL`, `LLM_API_KEY`, `LLM_MODEL` para cualquier endpoint compatible con OpenAI. Las migraciones corren solas al arrancar.

pey no tiene sandbox. Mientras `PEY_TEST_AMOUNT_OVERRIDE` esté definido, todo cobro real se envía por ese monto (por ejemplo `0.01`).

Para probar sin pagar de verdad, arranca el API con `ENABLE_DEV_ROUTES=true` y compila la app con `--dart-define=DEMO_MODE=true`; aparece un botón "Simular pago". Esas rutas se bloquean en producción y nunca deben exponerse a internet.

## Pruebas

```
cd apps/api && npm test            # 26 pruebas
cd apps/app && flutter analyze && flutter test     # 43 pruebas
```

## Estado y límites conocidos

- Probado de punta a punta: pago real de $0.01 por CoDi con webhook firmado, base en Turso, POS, inventario, pedidos, compra del cliente y asistente de IA.
- El APK de Android compila, pero no se ha instalado en un dispositivo. iOS no se ha compilado.
- El asistente usa un modelo gratuito (Qwen en Groq): tiene un límite de uso por minuto y puede responder "ocupado" si se le exige en ráfaga.
- El paquete `phosphor_flutter` no compila con este SDK de Flutter, así que la mayoría de los iconos son de Material y la landing usa Phosphor.
- La entrada por voz del asistente no está implementada.
- Aún no hay licencia definida.

## Despliegue

Ver `docs/DEPLOY.md` (API en Render, base en Turso, sitios estáticos aparte).
