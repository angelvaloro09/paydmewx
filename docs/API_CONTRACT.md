# PaydMex API contract (apps/api)

JSON over HTTPS. Auth: `Authorization: Bearer <jwt>` (except where marked public). Money = integer centavos. IDs = ULID strings. Timestamps = unix seconds.
Errors: `{ "error": { "code": string, "message": string } }` with proper HTTP status.

## Auth / profile
| Method | Path | Notes |
|---|---|---|
| POST | /auth/register | `{email, password(min 8), name}` → `{token, user}` (public) |
| POST | /auth/login | `{email, password}` → `{token, user}` (public) |
| GET | /me | `{user, business|null}` |
| POST | /me/business | convert to business: `{name, category, prepType, description?, address?, lat?, lng?}` → business. 409 if already has one |
| PATCH | /me/business | partial update; also `{clabe}` (registers via pey `POST /bank-account`, stores `peyBankAccountId`, `codiStatus`) |

## Discovery (public)
| GET | /businesses?category=&prepType=&q= | list active businesses |
| GET | /businesses/:id | detail |
| GET | /businesses/:id/products | active products |

## Owner: products & inventory (requires business)
| GET | /business/products | all |
| POST | /business/products | `{name, priceCents, trackStock, stock, prepMinutes?, imageUrl?}` |
| PATCH | /business/products/:id | partial |
| DELETE | /business/products/:id | soft (active=false) |
| POST | /business/products/:id/stock | `{delta, reason}` → writes `stock_movements` |
| GET | /business/inventory/low?threshold=5 | low stock list |
| GET | /business/sales/summary?from=&to= | `{totalCents, orders, topProducts[]}` |

## Orders & payments
| POST | /orders | `{businessId, items:[{productId, qty}], note?}` as customer; owner may omit auth-customer (walk-in) when `businessId` is their own. Validates stock, snapshots prices. |
| GET | /orders/:id | order + items + payment state (owner of business or order customer) |
| GET | /orders?role=customer|business&status= | lists |
| POST | /orders/:id/pay | creates pey CoDi QR → `{qrString, codiQrId, expiresAt, amountCents}` |
| PATCH | /orders/:id/status | owner: `preparing|ready|delivered|cancelled` (only valid transitions) |
| POST | /webhooks/pey | pey callbacks. Public route; verify Standard Webhooks signature on raw body, idempotent on `webhook-id` |

## AI
| POST | /ai/assist | `{message, history?[]}` → `{reply, actions[]}`; tool-calling (see ARCHITECTURE). Rate-limited per user |

## Health
| GET | /health | `{ok:true}` (public) |

## pey integration notes (docs.pey.mx, spec 2026-10-20)
- Base `https://api.pey.mx`, `Authorization: Bearer PEY_API_KEY`. No sandbox.
- `POST /codi/qr` body: `{amount(pesos), concept, expiration(0 or >=360), numRef(digits<=7), generateImage, bankAccountId?, metadata{}}` → `{id, qrString, qrImage|null}`.
- `POST /bank-account` body: `{alias, name, clabe, entity: BUSINESS|PERSON}` → `{id, codiStatus: PENDING}`; webhook `bank.account.updated` fires on ACTIVE.
- Webhook `codi.qr.payment_received`: `{type, amount, codiQrId, transactionId, datePaid, numRef, concept, bankAccountId?, metadata{externalMetadata}}`.
- pey errors: `{error:{message,type,requestId}}`; map to our 502 with code `PEY_ERROR`.
