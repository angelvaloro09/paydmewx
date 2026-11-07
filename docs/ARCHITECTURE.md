# PaydMewx — Architecture

Working name: **PaydMewx** (pay + me + mx). POS + CoDi payments + inventory + AI assistant for CDMX merchants, from street stalls to malls.
Hackathon: DevDay Exchange Community Hackathon CDMX. Submission due **Sun 2026-11-08 13:00**. Theme: public-good tools with AI + CoDi via pey.

## Components
```
Flutter app (mobile+web) ──HTTPS/JWT──> apps/api (Fastify) ──Bearer key──> https://api.pey.mx
                                            │  ▲                              │
                                            │  └──── webhook (Standard Webhooks) ┘
                                            ├── libsql/SQLite (Turso in prod)
                                            └── LLM (OpenAI-compatible endpoint)
apps/landing: static marketing site
```

## Domain
- **User**: one account. Can be customer, business owner, or both (`business` is optional 1:1 owner relation; "convert to business" = create business row). No separate account types.
- **Business**: `category` ∈ food | tailoring | footwear | clothing | department | grocery | services | other; `prepType` ∈ `instant` | `made_to_order` (decides whether orders go through preparing → ready).
- **Product**: price (centavos), `trackStock`, `stock`, `prepMinutes` (made_to_order only), `active`.
- **Order**: items snapshot, `total` centavos, status flow:
  `pending_payment → paid → (preparing → ready →)? delivered`; `cancelled`/`expired` from pending_payment. `instant` businesses skip preparing/ready.
  Created by a customer (app) or by the owner at the POS (walk-in, `customerId` null).
- **Payment**: one per order attempt; stores pey `codiQrId` (IDC) and later `transactionId`.

## Payment flow (CoDi QR)
1. `POST /orders` creates order (`pending_payment`).
2. `POST /orders/:id/pay` → api calls pey `POST /codi/qr` (amount, concept `Order <short id>`, numRef, expiration 600, metadata `{orderId}`, generateImage false). Returns `qrString` to the client, which renders the QR locally.
3. Payer pays in their banking app. pey calls `POST /webhooks/pey` (`codi.qr.payment_received`). API verifies signature on the **raw body**, dedupes on `webhook-id`, matches order via `metadata.externalMetadata.orderId` (fallback: `codiQrId`), marks paid, decrements stock in the same DB transaction.
4. Client polls `GET /orders/:id` (2s) as fallback/UX.
Push alternative (`/codi/pn` with phone number) and payment links are secondary.

## AI assistant
`POST /ai/assist` with tool-calling against any OpenAI-compatible endpoint (`LLM_BASE_URL/LLM_API_KEY/LLM_MODEL`), starting on a free model, swappable to OpenAI by env only. Tools are thin wrappers over existing services:
- Owner: `record_sale`, `adjust_stock`, `list_low_stock`, `sales_summary`, `create_product`.
- Customer: `search_businesses`, `reorder_last`.
The LLM never touches money directly: `record_sale` only creates a `pending_payment` order for the owner to confirm/charge.

## Frontend structure
Flutter feature-first: `lib/features/{auth,home,pos,inventory,orders,discover,ai,settings}`, `lib/core/{api,theme,a11y,router}`. One design system (tokens in `core/theme`). Responsive layouts: bottom-nav on phone, side-rail on web ≥ 900px.

## Delivery
- Repo private until submission, then public.
- Each task = one brief in `tasks/`, one coder conversation, then architect audit → fix → commit → push.
