-- PaydMex baseline. Port of apps/api/src/db/migrate.ts (SQLite) to Postgres.
-- Conventions: snake_case, ULID ids as TEXT, money in integer centavos (BIGINT),
-- timestamps are unix SECONDS in BIGINT (same unit as the Node API and docs/API_CONTRACT.md).

CREATE TABLE users (
    id            TEXT PRIMARY KEY,
    email         TEXT   NOT NULL UNIQUE,
    password_hash TEXT   NOT NULL,
    name          TEXT   NOT NULL,
    created_at    BIGINT NOT NULL
);

CREATE TABLE businesses (
    id                  TEXT PRIMARY KEY,
    owner_id            TEXT             NOT NULL UNIQUE REFERENCES users (id),
    name                TEXT             NOT NULL,
    description         TEXT,
    category            TEXT             NOT NULL,
    prep_type           TEXT             NOT NULL,
    address             TEXT,
    lat                 DOUBLE PRECISION,
    lng                 DOUBLE PRECISION,
    active              BOOLEAN          NOT NULL DEFAULT TRUE,
    pey_bank_account_id TEXT,
    clabe               TEXT,
    codi_status         TEXT,
    created_at          BIGINT           NOT NULL,
    CONSTRAINT ck_businesses_category CHECK (category IN
        ('food', 'tailoring', 'footwear', 'clothing', 'department', 'grocery', 'services', 'other')),
    CONSTRAINT ck_businesses_prep_type CHECK (prep_type IN ('instant', 'made_to_order'))
);

CREATE TABLE products (
    id           TEXT PRIMARY KEY,
    business_id  TEXT    NOT NULL REFERENCES businesses (id),
    name         TEXT    NOT NULL,
    price_cents  BIGINT  NOT NULL,
    track_stock  BOOLEAN NOT NULL DEFAULT TRUE,
    stock        INTEGER NOT NULL DEFAULT 0,
    prep_minutes INTEGER,
    image_url    TEXT,
    active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at   BIGINT  NOT NULL,
    CONSTRAINT ck_products_price CHECK (price_cents >= 0),
    CONSTRAINT ck_products_stock CHECK (stock >= 0),
    CONSTRAINT ck_products_prep_minutes CHECK (prep_minutes IS NULL OR prep_minutes >= 0)
);

CREATE TABLE stock_movements (
    id         TEXT PRIMARY KEY,
    product_id TEXT    NOT NULL REFERENCES products (id),
    delta      INTEGER NOT NULL,
    reason     TEXT    NOT NULL,
    created_at BIGINT  NOT NULL
);

CREATE TABLE orders (
    id          TEXT PRIMARY KEY,
    business_id TEXT   NOT NULL REFERENCES businesses (id),
    customer_id TEXT REFERENCES users (id),
    status      TEXT   NOT NULL,
    total_cents BIGINT NOT NULL,
    note        TEXT,
    created_at  BIGINT NOT NULL,
    paid_at     BIGINT,
    CONSTRAINT ck_orders_status CHECK (status IN
        ('pending_payment', 'paid', 'preparing', 'ready', 'delivered', 'cancelled', 'expired')),
    CONSTRAINT ck_orders_total CHECK (total_cents >= 0)
);

CREATE TABLE order_items (
    id          TEXT PRIMARY KEY,
    order_id    TEXT    NOT NULL REFERENCES orders (id),
    product_id  TEXT    NOT NULL REFERENCES products (id),
    name        TEXT    NOT NULL,
    price_cents BIGINT  NOT NULL,
    qty         INTEGER NOT NULL,
    CONSTRAINT ck_order_items_price CHECK (price_cents >= 0),
    CONSTRAINT ck_order_items_qty CHECK (qty > 0)
);

-- payments.status is free text on purpose: the Node API writes 'pending'/'paid' and may add values.
CREATE TABLE payments (
    id             TEXT PRIMARY KEY,
    order_id       TEXT   NOT NULL REFERENCES orders (id),
    codi_qr_id     TEXT,
    qr_string      TEXT,
    expires_at     BIGINT,
    transaction_id TEXT,
    status         TEXT   NOT NULL,
    amount_cents   BIGINT NOT NULL,
    created_at     BIGINT NOT NULL,
    CONSTRAINT ck_payments_amount CHECK (amount_cents >= 0)
);

-- id = pey `webhook-id` header; the PK is the dedupe mechanism.
CREATE TABLE webhook_events (
    id          TEXT PRIMARY KEY,
    received_at BIGINT NOT NULL
);

CREATE INDEX idx_businesses_category ON businesses (category);
CREATE INDEX idx_businesses_prep_type ON businesses (prep_type);
CREATE INDEX idx_products_business_id ON products (business_id);
CREATE INDEX idx_stock_movements_product_id ON stock_movements (product_id);
CREATE INDEX idx_orders_business_id ON orders (business_id);
CREATE INDEX idx_orders_customer_id ON orders (customer_id);
CREATE INDEX idx_order_items_order_id ON order_items (order_id);
CREATE INDEX idx_order_items_product_id ON order_items (product_id);
CREATE INDEX idx_payments_order_id ON payments (order_id);
CREATE INDEX idx_payments_codi_qr_id ON payments (codi_qr_id);
