// One ordered scenario, replayed against both backends. Everything target-specific (ids, tokens)
// is captured from that target's own responses; the runner normalizes and diffs the recordings.
import { signWebhook, makeClabe, deriveNumRef, toolCall } from './lib.mjs';

const PW = 'parity-pass-123';

export async function scenario(t) {
  const { call, check, record, pey, llm, secret } = t;
  const now = () => Math.floor(Date.now() / 1000);
  const auth = (token) => ({ token });

  const webhook = (label, payload, { id, ts = now(), tamper = false, omit = false } = {}) => {
    const raw = JSON.stringify(payload);
    const headers = omit ? {} : signWebhook(secret, id, ts, tamper ? raw + ' ' : raw);
    return call(label, 'POST', '/webhooks/pey', { raw, headers });
  };

  // ---------- health + auth ----------
  await call('health', 'GET', '/health');
  const alice = await call('register alice', 'POST', '/auth/register', { body: { email: 'alice@parity.test', password: PW, name: 'Alice Owner' } });
  await call('register duplicate', 'POST', '/auth/register', { body: { email: 'alice@parity.test', password: PW, name: 'Alice Owner' } });
  await call('register duplicate (case)', 'POST', '/auth/register', { body: { email: 'ALICE@parity.test', password: PW, name: 'Alice Owner' } });
  await call('register short password', 'POST', '/auth/register', { body: { email: 'x@parity.test', password: 'short', name: 'X' } });
  await call('register bad email', 'POST', '/auth/register', { body: { email: 'not-an-email', password: PW, name: 'X' } });
  await call('register missing name', 'POST', '/auth/register', { body: { email: 'y@parity.test', password: PW } });
  await call('register empty body', 'POST', '/auth/register', { body: {} });
  await call('register malformed json', 'POST', '/auth/register', { raw: '{"email":', headers: { 'content-type': 'application/json' } });
  const loginA = await call('login alice', 'POST', '/auth/login', { body: { email: 'alice@parity.test', password: PW } });
  await call('login wrong password', 'POST', '/auth/login', { body: { email: 'alice@parity.test', password: 'nope-nope-1' } });
  await call('login unknown user', 'POST', '/auth/login', { body: { email: 'ghost@parity.test', password: PW } });
  await call('login missing password', 'POST', '/auth/login', { body: { email: 'alice@parity.test' } });
  const A = loginA.body?.token ?? alice.body?.token;
  const bob = await call('register bob', 'POST', '/auth/register', { body: { email: 'bob@parity.test', password: PW, name: 'Bob Customer' } });
  const B = bob.body?.token;
  const carol = await call('register carol', 'POST', '/auth/register', { body: { email: 'carol@parity.test', password: PW, name: 'Carol Owner' } });
  const C = carol.body?.token;

  await call('me no token', 'GET', '/me');
  await call('me bad token', 'GET', '/me', { token: 'not.a.jwt' });
  await call('me alice (no business)', 'GET', '/me', auth(A));
  await call('unknown route', 'GET', '/nope', auth(A));

  // ---------- business ----------
  await call('business create no auth', 'POST', '/me/business', { body: { name: 'X', category: 'food', prepType: 'instant' } });
  await call('business create missing name', 'POST', '/me/business', { ...auth(A), body: { category: 'food', prepType: 'instant' } });
  await call('business create bad category', 'POST', '/me/business', { ...auth(A), body: { name: 'Tacos', category: 'spaceships', prepType: 'instant' } });
  await call('business create bad prepType', 'POST', '/me/business', { ...auth(A), body: { name: 'Tacos', category: 'food', prepType: 'slow' } });
  const biz = await call('business create', 'POST', '/me/business', {
    ...auth(A),
    body: { name: 'Tacos El Parity', category: 'food', prepType: 'instant', description: 'Tacos al pastor', address: 'Calle 1, CDMX', lat: 19.43, lng: -99.13 },
  });
  const bizId = biz.body?.id;
  await call('business create again', 'POST', '/me/business', { ...auth(A), body: { name: 'Otro', category: 'food', prepType: 'instant' } });
  await call('me alice (business)', 'GET', '/me', auth(A));
  await call('business patch fields', 'PATCH', '/me/business', { ...auth(A), body: { description: 'Los mejores', address: 'Calle 2', name: 'Tacos El Parity 2' } });
  await call('business patch nulls', 'PATCH', '/me/business', { ...auth(A), body: { description: null } });
  await call('business patch empty', 'PATCH', '/me/business', { ...auth(A), body: {} });
  await call('business patch bad category', 'PATCH', '/me/business', { ...auth(A), body: { category: 'zzz' } });
  await call('business patch no business', 'PATCH', '/me/business', { ...auth(B), body: { name: 'N' } });
  await call('business patch bad clabe', 'PATCH', '/me/business', { ...auth(A), body: { clabe: '123' } });
  await call('business patch clabe wrong check digit', 'PATCH', '/me/business', { ...auth(A), body: { clabe: '002010000000000019' } });
  await call('business patch clabe', 'PATCH', '/me/business', { ...auth(A), body: { clabe: makeClabe() } });
  const meBank = await call('me after clabe', 'GET', '/me', auth(A));
  const bankAccountId = meBank.body?.business?.peyBankAccountId ?? 'ba_stub_1';
  record('pey requests after clabe', pey.requests.slice());
  await webhook('webhook bank.account.updated', { type: 'bank.account.updated', data: { id: bankAccountId } }, { id: 'evt_bank_1' });
  await call('me after bank active', 'GET', '/me', auth(A));
  await call('business create (carol)', 'POST', '/me/business', {
    ...auth(C), body: { name: 'Sastreria Carol', category: 'tailoring', prepType: 'made_to_order', description: 'Arreglos' },
  });

  // ---------- discovery ----------
  await call('discovery list', 'GET', '/businesses');
  await call('discovery category', 'GET', '/businesses?category=tailoring');
  await call('discovery prepType', 'GET', '/businesses?prepType=made_to_order');
  await call('discovery q', 'GET', '/businesses?q=parity');
  await call('discovery q no match', 'GET', '/businesses?q=zzzzzz');
  await call('discovery bad category', 'GET', '/businesses?category=zzz');
  await call('discovery detail', 'GET', `/businesses/${bizId}`);
  await call('discovery detail unknown', 'GET', '/businesses/01ARZ3NDEKTSV4RRFFQ69G5FAV');
  await call('discovery products (empty)', 'GET', `/businesses/${bizId}/products`);

  // ---------- products & inventory ----------
  await call('products no auth', 'GET', '/business/products');
  await call('products as non-owner', 'GET', '/business/products', auth(B));
  await call('product create bad price', 'POST', '/business/products', { ...auth(A), body: { name: 'X', priceCents: -5, trackStock: false, stock: 0 } });
  await call('product create missing name', 'POST', '/business/products', { ...auth(A), body: { priceCents: 500, trackStock: false, stock: 0 } });
  await call('product create float price', 'POST', '/business/products', { ...auth(A), body: { name: 'X', priceCents: 10.5, trackStock: false, stock: 0 } });
  const pTaco = await call('product create taco', 'POST', '/business/products', { ...auth(A), body: { name: 'Taco al pastor', priceCents: 2500, trackStock: true, stock: 10, prepMinutes: 5 } });
  const pAgua = await call('product create agua', 'POST', '/business/products', { ...auth(A), body: { name: 'Agua de horchata', priceCents: 3000, trackStock: false, stock: 0, imageUrl: 'https://example.com/a.png' } });
  const pLow = await call('product create low', 'POST', '/business/products', { ...auth(A), body: { name: 'Salsa verde', priceCents: 1000, trackStock: true, stock: 2 } });
  const tacoId = pTaco.body?.id, aguaId = pAgua.body?.id, lowId = pLow.body?.id;
  await call('products list', 'GET', '/business/products', auth(A));
  await call('product patch', 'PATCH', `/business/products/${tacoId}`, { ...auth(A), body: { priceCents: 2600, name: 'Taco pastor' } });
  await call('product patch bad', 'PATCH', `/business/products/${tacoId}`, { ...auth(A), body: { priceCents: -1 } });
  await call('product patch empty', 'PATCH', `/business/products/${tacoId}`, { ...auth(A), body: {} });
  await call('product patch unknown', 'PATCH', '/business/products/01ARZ3NDEKTSV4RRFFQ69G5FAV', { ...auth(A), body: { name: 'x' } });
  await call('product patch other owner', 'PATCH', `/business/products/${tacoId}`, { ...auth(C), body: { name: 'hack' } });
  await call('stock +5', 'POST', `/business/products/${tacoId}/stock`, { ...auth(A), body: { delta: 5, reason: 'restock' } });
  await call('stock below zero', 'POST', `/business/products/${tacoId}/stock`, { ...auth(A), body: { delta: -999, reason: 'oops' } });
  await call('stock zero delta', 'POST', `/business/products/${tacoId}/stock`, { ...auth(A), body: { delta: 0, reason: 'x' } });
  await call('stock missing reason', 'POST', `/business/products/${tacoId}/stock`, { ...auth(A), body: { delta: 1 } });
  await call('stock untracked product', 'POST', `/business/products/${aguaId}/stock`, { ...auth(A), body: { delta: 1, reason: 'x' } });
  await call('stock -5', 'POST', `/business/products/${tacoId}/stock`, { ...auth(A), body: { delta: -5, reason: 'merma' } });
  await call('inventory low default', 'GET', '/business/inventory/low', auth(A));
  await call('inventory low threshold', 'GET', '/business/inventory/low?threshold=20', auth(A));
  await call('inventory low bad threshold', 'GET', '/business/inventory/low?threshold=abc', auth(A));
  await call('sales summary empty', 'GET', '/business/sales/summary', auth(A));
  const tmp = await call('product create temp', 'POST', '/business/products', { ...auth(A), body: { name: 'Temporal', priceCents: 100, trackStock: false, stock: 0 } });
  await call('product delete', 'DELETE', `/business/products/${tmp.body?.id}`, auth(A));
  await call('product delete again', 'DELETE', `/business/products/${tmp.body?.id}`, auth(A));
  await call('products list after delete', 'GET', '/business/products', auth(A));
  await call('discovery products (active only)', 'GET', `/businesses/${bizId}/products`);

  // ---------- orders ----------
  const item = (productId, qty) => ({ productId, qty });
  await call('order no auth', 'POST', '/orders', { body: { businessId: bizId, items: [item(tacoId, 1)] } });
  await call('order empty items', 'POST', '/orders', { ...auth(B), body: { businessId: bizId, items: [] } });
  await call('order qty 0', 'POST', '/orders', { ...auth(B), body: { businessId: bizId, items: [item(tacoId, 0)] } });
  await call('order unknown business', 'POST', '/orders', { ...auth(B), body: { businessId: '01ARZ3NDEKTSV4RRFFQ69G5FAV', items: [item(tacoId, 1)] } });
  await call('order unknown product', 'POST', '/orders', { ...auth(B), body: { businessId: bizId, items: [item('01ARZ3NDEKTSV4RRFFQ69G5FAV', 1)] } });
  await call('order insufficient stock', 'POST', '/orders', { ...auth(B), body: { businessId: bizId, items: [item(lowId, 99)] } });
  await call('order with null note', 'POST', '/orders', { ...auth(B), body: { businessId: bizId, items: [item(aguaId, 1)] , note: null } });
  const o1 = await call('order create bob', 'POST', '/orders', { ...auth(B), body: { businessId: bizId, items: [item(tacoId, 3), item(aguaId, 2)], note: 'sin cebolla' } });
  const o1Id = o1.body?.id;
  const oWalk = await call('order create walk-in (owner)', 'POST', '/orders', { ...auth(A), body: { businessId: bizId, items: [item(aguaId, 1)] } });
  await call('order get bob', 'GET', `/orders/${o1Id}`, auth(B));
  await call('order get owner', 'GET', `/orders/${o1Id}`, auth(A));
  await call('order get stranger (carol)', 'GET', `/orders/${o1Id}`, auth(C));
  await call('order get unknown', 'GET', '/orders/01ARZ3NDEKTSV4RRFFQ69G5FAV', auth(B));
  await call('order get no auth', 'GET', `/orders/${o1Id}`);
  await call('orders list customer', 'GET', '/orders?role=customer', auth(B));
  await call('orders list business', 'GET', '/orders?role=business', auth(A));
  await call('orders list business as non-owner', 'GET', '/orders?role=business', auth(B));
  await call('orders list default', 'GET', '/orders', auth(B));
  await call('orders list status filter', 'GET', '/orders?role=business&status=pending_payment', auth(A));
  await call('orders list bad status', 'GET', '/orders?status=zzz', auth(B));
  await call('orders list bad role', 'GET', '/orders?role=admin', auth(B));

  // pay
  await call('pay no auth', 'POST', `/orders/${o1Id}/pay`);
  await call('pay stranger', 'POST', `/orders/${o1Id}/pay`, auth(C));
  pey.requests.length = 0;
  pey.failNext = true;
  await call('pay pey failure', 'POST', `/orders/${o1Id}/pay`, auth(B));
  const pay = await call('pay bob', 'POST', `/orders/${o1Id}/pay`, auth(B));
  const pay2 = await call('pay again (idempotent)', 'POST', `/orders/${o1Id}/pay`, auth(B));
  check('pay idempotent returns same qr', pay.body?.codiQrId === pay2.body?.codiQrId);
  const created = now();
  check('pay expiresAt about +600s', Math.abs((pay.body?.expiresAt ?? 0) - (created + 600)) <= 10);
  check('pey called once per successful QR (1 failed + 1 ok)', pey.requests.filter((r) => r.url === '/codi/qr').length === 2);
  // Outbound pey payload: numRef must be derive(orderId); everything else compared verbatim.
  const peyCalls = pey.requests.filter((r) => r.url === '/codi/qr').map((r) => ({
    auth: r.auth,
    body: {
      ...r.body,
      numRef: r.body?.numRef === deriveNumRef(o1Id) ? '<derived>' : r.body?.numRef,
      concept: r.body?.concept === `Pedido ${o1Id.slice(-6)}` ? 'Pedido <last6>' : r.body?.concept,
    },
  }));
  record('pey outbound /codi/qr', peyCalls);
  await call('pay owner-initiated walk-in', 'POST', `/orders/${oWalk.body?.id}/pay`, auth(A));
  await call('status on pending (preparing)', 'PATCH', `/orders/${o1Id}/status`, { ...auth(A), body: { status: 'preparing' } });

  // webhook
  const qrId = pay.body?.codiQrId;
  const paidPayload = {
    type: 'codi.qr.payment_received', amount: 26, codiQrId: qrId, transactionId: 'tx_parity_1',
    datePaid: new Date().toISOString(), numRef: deriveNumRef(o1Id), concept: 'Pedido',
    metadata: { externalMetadata: { orderId: o1Id } },
  };
  await webhook('webhook missing headers', paidPayload, { omit: true });
  await webhook('webhook tampered body', paidPayload, { id: 'evt_pay_bad', tamper: true });
  await webhook('webhook stale timestamp', paidPayload, { id: 'evt_pay_old', ts: now() - 3600 });
  await call('webhook non-json body', 'POST', '/webhooks/pey', { raw: 'hello', headers: signWebhook(secret, 'evt_junk', now(), 'hello') });
  await call('order still pending after bad webhooks', 'GET', `/orders/${o1Id}`, auth(B));
  await webhook('webhook unknown event type', { type: 'something.else', data: {} }, { id: 'evt_other' });
  await webhook('webhook unknown qr', { ...paidPayload, codiQrId: 'qr_unknown', metadata: {} }, { id: 'evt_unknown' });
  await webhook('webhook payment received', paidPayload, { id: 'evt_pay_1' });
  await webhook('webhook duplicate', paidPayload, { id: 'evt_pay_1' });
  await webhook('webhook replay new id (already paid)', paidPayload, { id: 'evt_pay_2' });
  await call('order paid', 'GET', `/orders/${o1Id}`, auth(B));
  await call('products after paid (stock taken)', 'GET', '/business/products', auth(A));
  await call('pay already paid', 'POST', `/orders/${o1Id}/pay`, auth(B));
  await call('sales summary after paid', 'GET', '/business/sales/summary', auth(A));
  await call('sales summary range', 'GET', `/business/sales/summary?from=0&to=${now() + 86400}`, auth(A));
  await call('sales summary future range', 'GET', `/business/sales/summary?from=${now() + 86400}&to=${now() + 172800}`, auth(A));
  await call('sales summary bad range', 'GET', '/business/sales/summary?from=abc', auth(A));
  await call('sales summary as non-owner', 'GET', '/business/sales/summary', auth(B));

  // status machine
  const st = (label, who, status, id = o1Id) => call(label, 'PATCH', `/orders/${id}/status`, { ...auth(who), body: { status } });
  await st('status by customer (forbidden)', B, 'preparing');
  await st('status by stranger owner', C, 'preparing');
  await st('status invalid value', A, 'bogus');
  await st('status to paid (not allowed)', A, 'paid');
  await st('status paid->ready (skip)', A, 'ready');
  await st('status paid->preparing', A, 'preparing');
  await st('status preparing->ready', A, 'ready');
  await st('status ready->preparing (backwards)', A, 'preparing');
  await st('status ready->delivered', A, 'delivered');
  await st('status delivered->cancelled', A, 'cancelled');
  await call('status missing body', 'PATCH', `/orders/${o1Id}/status`, { ...auth(A), body: {} });
  await call('status unknown order', 'PATCH', '/orders/01ARZ3NDEKTSV4RRFFQ69G5FAV/status', { ...auth(A), body: { status: 'preparing' } });
  await call('orders list status=delivered', 'GET', '/orders?role=business&status=delivered', auth(A));

  // cancel paid order restores stock; cancel pending order does not touch stock
  const o2 = await call('order create 2 (cancel after paid)', 'POST', '/orders', { ...auth(B), body: { businessId: bizId, items: [item(tacoId, 4)] } });
  const o2Id = o2.body?.id;
  const pay3 = await call('pay order 2', 'POST', `/orders/${o2Id}/pay`, auth(B));
  await webhook('webhook order 2 paid', { type: 'codi.qr.payment_received', codiQrId: pay3.body?.codiQrId, transactionId: 'tx_parity_2', metadata: {} }, { id: 'evt_pay_3' });
  await call('products before cancel', 'GET', '/business/products', auth(A));
  await st('cancel paid order 2', A, 'cancelled', o2Id);
  await call('products after cancel (stock restored)', 'GET', '/business/products', auth(A));
  await call('stock movements ledger (via low inventory)', 'GET', '/business/inventory/low?threshold=100', auth(A));
  const o3 = await call('order create 3 (cancel pending)', 'POST', '/orders', { ...auth(B), body: { businessId: bizId, items: [item(tacoId, 1)] } });
  await st('cancel pending order 3', A, 'cancelled', o3.body?.id);
  await call('products after cancel pending', 'GET', '/business/products', auth(A));
  await call('pay cancelled order', 'POST', `/orders/${o3.body?.id}/pay`, auth(B));

  // made_to_order business (carol): paid -> preparing -> ready -> delivered, plus the forbidden edges
  const carolBiz = (await call('me carol', 'GET', '/me', auth(C))).body?.business?.id;
  const pCoat = await call('mto product create', 'POST', '/business/products', { ...auth(C), body: { name: 'Ajuste de saco', priceCents: 15000, trackStock: true, stock: 5, prepMinutes: 120 } });
  const coatId = pCoat.body?.id;
  const mtoPaid = async (label, qty) => {
    const o = await call(`${label} create`, 'POST', '/orders', { ...auth(B), body: { businessId: carolBiz, items: [item(coatId, qty)] } });
    const pq = await call(`${label} pay`, 'POST', `/orders/${o.body?.id}/pay`, auth(B));
    await webhook(`${label} webhook`, { type: 'codi.qr.payment_received', codiQrId: pq.body?.codiQrId, transactionId: `tx_${label}`, metadata: {} }, { id: `evt_${label.replace(/\W/g, '_')}` });
    return o.body?.id;
  };
  const m1 = await mtoPaid('mto order 1', 2);
  await st('mto paid->ready (skip)', C, 'ready', m1);
  await st('mto paid->preparing', C, 'preparing', m1);
  await st('mto preparing->delivered (skip)', C, 'delivered', m1);
  await st('mto preparing->cancelled', C, 'cancelled', m1);
  await st('mto preparing->ready', C, 'ready', m1);
  await st('mto ready->cancelled', C, 'cancelled', m1);
  await st('mto ready->delivered', C, 'delivered', m1);
  await st('mto delivered->preparing', C, 'preparing', m1);
  await call('mto stock after delivered', 'GET', '/business/products', auth(C));
  const m2 = await mtoPaid('mto order 2', 1);
  await st('mto paid->delivered (direct)', C, 'delivered', m2);
  const m3 = await mtoPaid('mto order 3', 2);
  await st('mto paid->cancelled', C, 'cancelled', m3);
  await call('mto stock after cancel', 'GET', '/business/products', auth(C));
  await call('mto sales summary', 'GET', '/business/sales/summary', auth(C));
  await call('mto orders list business', 'GET', '/orders?role=business', auth(C));
  await call('mto orders list customer by status', 'GET', '/orders?role=customer&status=cancelled', auth(B));

  // dev route (Node has it behind ENABLE_DEV_ROUTES; Spring must too)
  const o4 = await call('order create 4 (dev simulate)', 'POST', '/orders', { ...auth(B), body: { businessId: bizId, items: [item(tacoId, 1)] } });
  await call('dev simulate-paid', 'POST', `/dev/orders/${o4.body?.id}/simulate-paid`);
  await call('order 4 after simulate-paid', 'GET', `/orders/${o4.body?.id}`, auth(B));

  // ---------- AI ----------
  const aiReq = (label, who, message, history) => call(label, 'POST', '/ai/assist', { ...auth(who), body: history ? { message, history } : { message } });
  await call('ai no auth', 'POST', '/ai/assist', { body: { message: 'hola' } });
  await aiReq('ai empty message', A, '   ');
  await aiReq('ai too long', A, 'x'.repeat(1001));
  await call('ai bad history role', 'POST', '/ai/assist', { ...auth(A), body: { message: 'hola', history: [{ role: 'system', content: 'x' }] } });
  await call('ai history too long', 'POST', '/ai/assist', { ...auth(A), body: { message: 'hola', history: Array.from({ length: 11 }, () => ({ role: 'user', content: 'x' })) } });
  llm.requests.length = 0;
  await aiReq('ai plain reply (owner)', A, 'hola', [{ role: 'user', content: 'buenas' }, { role: 'assistant', content: 'que tal' }]);
  record('llm request owner plain', llm.requests.slice());
  llm.requests.length = 0;
  llm.script.push(toolCall('list_products', {}));
  await aiReq('ai list_products', A, 'que productos tengo?');
  record('llm requests list_products', llm.requests.slice());
  llm.script.push(toolCall('record_sale', { items: [{ productName: 'taco', qty: 2 }, { productName: 'inexistente', qty: 1 }] }));
  await aiReq('ai record_sale', A, 'vendi 2 tacos');
  llm.script.push(toolCall('adjust_stock', { productName: 'Salsa verde', delta: 3, reason: 'compra' }));
  await aiReq('ai adjust_stock', A, 'llegaron 3 salsas');
  llm.script.push(toolCall('list_low_stock', { threshold: 50 }));
  await aiReq('ai list_low_stock', A, 'que se acaba?');
  llm.script.push(toolCall('sales_summary', {}));
  await aiReq('ai sales_summary', A, 'cuanto vendi hoy?');
  llm.script.push(toolCall('create_product', { name: 'Quesadilla', priceCents: 4500, trackStock: true, stock: 8 }));
  await aiReq('ai create_product', A, 'agrega quesadilla a 45');
  llm.script.push(toolCall('delete_everything', {}));
  await aiReq('ai unknown tool', A, 'borra todo');
  llm.script.push({ role: 'assistant', content: '**Listo** `ok` \u{1F600}\n' });
  await aiReq('ai reply sanitizing', A, 'hola');
  llm.requests.length = 0;
  llm.script.push(toolCall('search_businesses', { query: 'parity' }));
  await aiReq('ai customer search_businesses', B, 'busca tacos');
  record('llm requests customer', llm.requests.slice());
  llm.script.push(toolCall('reorder_last', {}));
  await aiReq('ai customer reorder_last', B, 'repite mi ultimo pedido');
  llm.script.push(toolCall('record_sale', { items: [] }));
  await aiReq('ai customer calls owner tool', B, 'vende algo');
  const dave = (await call('register dave', 'POST', '/auth/register', { body: { email: 'dave@parity.test', password: PW, name: 'Dave' } })).body?.token;
  let limited = 0;
  for (let i = 0; i < 22; i++) {
    const r = await call(`ai rate-limit probe ${i + 1}`, 'POST', '/ai/assist', { ...auth(dave), body: { message: 'hola' } });
    if (r.status === 429) limited += 1;
  }
  check('ai rate limit: 20 ok then 429', limited === 2);

  // ---------- validation edge cases that may create rows on a lenient backend (kept last) ----------
  const erin = (await call('register erin', 'POST', '/auth/register', { body: { email: 'erin@parity.test', password: PW, name: 'Erin' } })).body?.token;
  await call('business create bad lat', 'POST', '/me/business', { ...auth(erin), body: { name: 'Tacos', category: 'food', prepType: 'instant', lat: 999, lng: 0 } });
}
