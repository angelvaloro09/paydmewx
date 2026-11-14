package mx.paydmex.api.order;

import java.time.Clock;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.TreeMap;
import java.util.function.Function;
import java.util.stream.Collectors;

import mx.paydmex.api.auth.UserRepository;
import mx.paydmex.api.business.BusinessLookup;
import mx.paydmex.api.business.BusinessLookup.BusinessRef;
import mx.paydmex.api.common.AppException;
import mx.paydmex.api.pey.PeyClient;
import mx.paydmex.api.pey.PeyClient.CodiQr;
import mx.paydmex.api.pey.PeyClient.CodiQrRequest;
import mx.paydmex.api.product.ProductLookup;
import mx.paydmex.api.product.ProductLookup.ProductSnapshot;
import mx.paydmex.api.product.StockLedger;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * Create / list / read orders and charge them with a CoDi QR. Stock is NOT reserved here (same as the Node API): it is
 * pre-checked at creation and taken when the payment webhook arrives ({@link PeyWebhookService}).
 */
@Service
public class OrderService {

	static final long ORDER_EXPIRY_SECONDS = 15 * 60;

	static final int CODI_QR_EXPIRATION_SECONDS = 600;

	public enum Role {
		CUSTOMER, BUSINESS
	}

	private record Access(PurchaseOrder order, BusinessRef business) {
	}

	/** Result of the DB phase of pay(): either a reusable QR, or what is needed to ask pey for a new one. */
	private record PayPlan(PayResponse existing, long amountCents, String businessId, String bankAccountId) {
	}

	private final OrderRepository orders;

	private final OrderItemRepository items;

	private final PaymentRepository payments;

	private final BusinessLookup businesses;

	private final ProductLookup products;

	private final UserRepository users;

	private final PeyClient pey;

	private final StockLedger stock;

	private final TransactionTemplate tx;

	private final Clock clock;

	OrderService(OrderRepository orders, OrderItemRepository items, PaymentRepository payments,
			BusinessLookup businesses, ProductLookup products, UserRepository users, PeyClient pey, StockLedger stock,
			PlatformTransactionManager txManager, Clock clock) {
		this.orders = orders;
		this.items = items;
		this.payments = payments;
		this.businesses = businesses;
		this.products = products;
		this.users = users;
		this.pey = pey;
		this.stock = stock;
		this.tx = new TransactionTemplate(txManager);
		this.clock = clock;
	}

	@Transactional
	public OrderDto create(String userId, CreateOrderRequest req) {
		if (!users.existsById(userId)) {
			throw new AppException(HttpStatus.UNAUTHORIZED, "UNAUTHORIZED", "User not found");
		}
		BusinessRef business = businesses.findActive(req.businessId())
			.orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "BUSINESS_NOT_FOUND", "Business not found"));

		var qtyByProduct = new LinkedHashMap<String, Long>();
		for (CreateOrderRequest.Line line : req.items()) {
			qtyByProduct.merge(line.productId(), (long) line.qty(), Long::sum);
		}
		Map<String, ProductSnapshot> byId = products.findActive(business.id(), qtyByProduct.keySet())
			.stream()
			.collect(Collectors.toMap(ProductSnapshot::id, Function.identity()));
		if (byId.size() != qtyByProduct.size()) {
			throw new AppException(HttpStatus.NOT_FOUND, "PRODUCT_NOT_FOUND",
					"One or more products do not exist or are inactive for this business");
		}
		for (var requested : qtyByProduct.entrySet()) {
			ProductSnapshot p = byId.get(requested.getKey());
			if (p.trackStock() && requested.getValue() > p.stock()) {
				throw new AppException(HttpStatus.CONFLICT, "INSUFFICIENT_STOCK",
						"Insufficient stock for product \"" + p.name() + "\"");
			}
		}

		long total = 0;
		try {
			for (CreateOrderRequest.Line line : req.items()) {
				total = Math.addExact(total, Math.multiplyExact(byId.get(line.productId()).priceCents(), line.qty()));
			}
		}
		catch (ArithmeticException ex) {
			throw new AppException(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "items: order total is too large");
		}

		String customerId = business.ownerId().equals(userId) ? null : userId;
		PurchaseOrder order = PurchaseOrder.create(business.id(), customerId, total, req.note(), now());
		var rows = new ArrayList<OrderItem>();
		for (CreateOrderRequest.Line line : req.items()) {
			ProductSnapshot p = byId.get(line.productId());
			rows.add(OrderItem.create(order.id(), p.id(), p.name(), p.priceCents(), line.qty()));
		}
		orders.save(order);
		items.saveAll(rows);
		return OrderDto.of(order, rows, null);
	}

	/** Not read-only: reading a stale pending order expires it (lazy expiry, like the Node API). */
	@Transactional
	public OrderDto get(String userId, String orderId) {
		PurchaseOrder order = requireAccess(userId, orderId).order();
		return hydrate(List.of(order)).getFirst();
	}

	/** Dev routes only: reads an order with no ownership check. */
	@Transactional
	OrderDto getUnchecked(String orderId) {
		return hydrate(List.of(orders.findById(orderId).orElseThrow(OrderService::notFound))).getFirst();
	}

	@Transactional
	public List<OrderDto> list(String userId, Role role, OrderStatus status) {
		Optional<String> ownBusinessId = businesses.findIdByOwner(userId);
		long cutoff = now() - ORDER_EXPIRY_SECONDS;
		List<String> stale = orders.findStaleIds(cutoff, userId, ownBusinessId.orElse(""));
		if (!stale.isEmpty()) {
			orders.expireStale(stale, cutoff);
			payments.expirePendingOfExpiredOrders(stale);
		}

		List<PurchaseOrder> found;
		if (role == Role.CUSTOMER) {
			found = orders.findByCustomerIdOrderByCreatedAtDescIdDesc(userId);
		}
		else if (role == Role.BUSINESS) {
			found = ownBusinessId.map(orders::findByBusinessIdOrderByCreatedAtDescIdDesc).orElse(List.of());
		}
		else if (ownBusinessId.isPresent()) {
			found = orders.findForCustomerOrBusiness(userId, ownBusinessId.get());
		}
		else {
			found = orders.findByCustomerIdOrderByCreatedAtDescIdDesc(userId);
		}
		if (status != null) {
			found = found.stream().filter(o -> o.status().equals(status.wire())).toList();
		}
		return hydrate(found);
	}

	/**
	 * Owner-only status change. The transition is one conditional UPDATE ({@code WHERE status = :from}) and, when a
	 * paid order is cancelled, the stock restore + {@code order_cancelled} movements run in the same transaction: a
	 * failure rolls the status back too, and two concurrent cancels restore the stock only once. An {@link AppException}
	 * (403/404/409) is thrown before any write of this method, so it must not roll back the lazy expiry that
	 * {@link #requireAccess} may have just persisted; unexpected errors still roll everything back.
	 */
	@Transactional(noRollbackFor = AppException.class)
	public OrderDto updateStatus(String userId, String orderId, OrderStatus next) {
		Access access = requireAccess(userId, orderId);
		PurchaseOrder order = access.order();
		if (!access.business().ownerId().equals(userId)) {
			throw new AppException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Only the business owner may update order status");
		}
		OrderStatus current = OrderStatus.fromWire(order.status()).orElse(null);
		if (current == null || !isValidOwnerTransition(current, next, access.business().madeToOrder())
				|| orders.transition(order.id(), current.wire(), next.wire()) == 0) {
			throw new AppException(HttpStatus.CONFLICT, "INVALID_TRANSITION",
					"Invalid status transition from " + order.status() + " to " + next.wire());
		}
		if (current == OrderStatus.PAID && next == OrderStatus.CANCELLED) {
			restock(order.id());
		}
		PurchaseOrder updated = orders.findById(order.id()).orElseThrow(OrderService::notFound);
		return hydrate(List.of(updated)).getFirst();
	}

	/** Same table as the Node API: instant businesses skip preparing/ready; only pending/paid orders can be cancelled. */
	static boolean isValidOwnerTransition(OrderStatus current, OrderStatus next, boolean madeToOrder) {
		return switch (current) {
			case PENDING_PAYMENT -> next == OrderStatus.CANCELLED;
			case PAID -> next == OrderStatus.DELIVERED || next == OrderStatus.CANCELLED
					|| (madeToOrder && next == OrderStatus.PREPARING);
			case PREPARING -> next == OrderStatus.READY;
			case READY -> next == OrderStatus.DELIVERED;
			case DELIVERED, CANCELLED, EXPIRED -> false;
		};
	}

	/** Products in id order, like the webhook, so concurrent stock writers lock rows in the same order. */
	private void restock(String orderId) {
		Map<String, Integer> qtyByProduct = new TreeMap<>();
		for (OrderItem item : items.findByOrderIdOrderByIdAsc(orderId)) {
			qtyByProduct.merge(item.productId(), item.qty(), Integer::sum);
		}
		long now = now();
		qtyByProduct.forEach((productId, qty) -> stock.recordRestock(productId, qty, now));
	}

	/**
	 * Creates (or reuses) the CoDi QR of a pending order. The pey HTTP call runs OUTSIDE any transaction so a slow pey
	 * never holds a DB connection: phase 1 reads/validates, phase 2 calls pey, phase 3 stores the payment.
	 */
	public PayResponse pay(String userId, String orderId) {
		PayPlan plan = tx.execute(status -> preparePay(userId, orderId));
		if (plan.existing() != null) {
			return plan.existing();
		}
		CodiQr qr = pey.createCodiQr(new CodiQrRequest(plan.amountCents(), "Pedido " + lastChars(orderId, 6),
				deriveNumRef(orderId), CODI_QR_EXPIRATION_SECONDS, plan.bankAccountId(),
				Map.of("orderId", orderId, "businessId", plan.businessId())));
		long createdAt = now();
		long expiresAt = createdAt + CODI_QR_EXPIRATION_SECONDS;
		tx.executeWithoutResult(status -> payments
			.save(Payment.pending(orderId, qr.id(), qr.qrString(), expiresAt, plan.amountCents(), createdAt)));
		return new PayResponse(qr.qrString(), qr.id(), expiresAt, plan.amountCents());
	}

	private PayPlan preparePay(String userId, String orderId) {
		Access access = requireAccess(userId, orderId);
		PurchaseOrder order = access.order();
		if (!OrderStatus.PENDING_PAYMENT.wire().equals(order.status())) {
			throw new AppException(HttpStatus.CONFLICT, "INVALID_TRANSITION", "Order is not pending payment");
		}
		long now = now();
		for (Payment p : payments.findByOrderIdAndStatusOrderByCreatedAtDescIdDesc(order.id(), Payment.PENDING)) {
			long expiresAt = p.expiresAt() != null ? p.expiresAt() : p.createdAt() + CODI_QR_EXPIRATION_SECONDS;
			if (p.codiQrId() != null && p.qrString() != null && expiresAt > now) {
				return new PayPlan(new PayResponse(p.qrString(), p.codiQrId(), expiresAt, p.amountCents()), 0, null,
						null);
			}
		}
		return new PayPlan(null, order.totalCents(), order.businessId(), access.business().codiBankAccountIdOrNull());
	}

	/** 404 for both "no such order" and "not yours", so ids cannot be probed. Expires the order if it is stale. */
	private Access requireAccess(String userId, String orderId) {
		PurchaseOrder order = orders.findById(orderId).orElseThrow(OrderService::notFound);
		BusinessRef business = businesses.findById(order.businessId()).orElseThrow(OrderService::notFound);
		boolean isOwner = business.ownerId().equals(userId);
		boolean isCustomer = userId.equals(order.customerId());
		if (!isOwner && !isCustomer) {
			throw notFound();
		}
		return new Access(expireIfStale(order), business);
	}

	private PurchaseOrder expireIfStale(PurchaseOrder order) {
		long cutoff = now() - ORDER_EXPIRY_SECONDS;
		if (!OrderStatus.PENDING_PAYMENT.wire().equals(order.status()) || order.createdAt() > cutoff) {
			return order;
		}
		orders.expireStale(List.of(order.id()), cutoff);
		payments.expirePendingOfExpiredOrders(List.of(order.id()));
		return orders.findById(order.id()).orElseThrow(OrderService::notFound);
	}

	private List<OrderDto> hydrate(List<PurchaseOrder> list) {
		if (list.isEmpty()) {
			return List.of();
		}
		List<String> ids = list.stream().map(PurchaseOrder::id).toList();
		Map<String, List<OrderItem>> itemsByOrder = items.findByOrderIdInOrderByIdAsc(ids)
			.stream()
			.collect(Collectors.groupingBy(OrderItem::orderId));
		var latestPayment = new LinkedHashMap<String, Payment>();
		for (Payment p : payments.findByOrderIdInOrderByCreatedAtDescIdDesc(ids)) {
			latestPayment.putIfAbsent(p.orderId(), p);
		}
		return list.stream()
			.map(o -> OrderDto.of(o, itemsByOrder.getOrDefault(o.id(), List.of()), latestPayment.get(o.id())))
			.toList();
	}

	/**
	 * pey's 7-digit {@code numRef} derived from the order id; same hash as the Node API (uint32 rolling 31x) so a
	 * given order keeps the same reference across the cutover.
	 */
	static String deriveNumRef(String orderId) {
		long hash = 0;
		for (int i = 0; i < orderId.length(); i++) {
			hash = (hash * 31 + orderId.charAt(i)) & 0xFFFFFFFFL;
		}
		return String.valueOf(1_000_000 + (hash % 9_000_000));
	}

	private static String lastChars(String s, int n) {
		return s.length() <= n ? s : s.substring(s.length() - n);
	}

	private long now() {
		return clock.instant().getEpochSecond();
	}

	private static AppException notFound() {
		return new AppException(HttpStatus.NOT_FOUND, "ORDER_NOT_FOUND", "Order not found");
	}

}
