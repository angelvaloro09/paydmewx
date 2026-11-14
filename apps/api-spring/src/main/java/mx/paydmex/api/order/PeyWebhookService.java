package mx.paydmex.api.order;

import java.time.Clock;
import java.util.Map;
import java.util.TreeMap;

import mx.paydmex.api.business.BusinessLookup;
import mx.paydmex.api.product.StockLedger;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.node.ObjectNode;

/**
 * Applies a verified pey webhook. {@link #process} is ONE transaction: the dedupe claim, the order/payment status
 * change and the stock decrements with their movements commit or roll back together. If anything fails the claim is
 * rolled back too, so pey's retry is processed instead of being swallowed as a duplicate.
 */
@Service
class PeyWebhookService {

	private static final Logger log = LoggerFactory.getLogger(PeyWebhookService.class);

	/** Webhook outcome; {@code duplicate} is true when the webhook-id was already processed. */
	record Result(boolean duplicate) {
	}

	private final WebhookEventRepository events;

	private final OrderRepository orders;

	private final OrderItemRepository items;

	private final PaymentRepository payments;

	private final BusinessLookup businesses;

	private final StockLedger stock;

	private final Clock clock;

	PeyWebhookService(WebhookEventRepository events, OrderRepository orders, OrderItemRepository items,
			PaymentRepository payments, BusinessLookup businesses, StockLedger stock, Clock clock) {
		this.events = events;
		this.orders = orders;
		this.items = items;
		this.payments = payments;
		this.businesses = businesses;
		this.stock = stock;
		this.clock = clock;
	}

	@Transactional
	Result process(String webhookId, ObjectNode payload) {
		long now = clock.instant().getEpochSecond();
		if (!events.claim(webhookId, now)) {
			return new Result(true);
		}
		JsonNode data = merged(payload);
		switch (text(payload, "type")) {
			case "codi.qr.payment_received" -> onPaymentReceived(data, now);
			case "bank.account.updated" -> onBankAccountUpdated(data);
			default -> {
				// other event types are acknowledged and ignored (the id stays claimed)
			}
		}
		return new Result(false);
	}

	private void onPaymentReceived(JsonNode data, long now) {
		String codiQrId = firstText(data, "codiQrId", "id");
		String transactionId = text(data, "transactionId");
		JsonNode metadata = data.path("metadata");
		String fallbackOrderId = firstNonNull(text(metadata.path("externalMetadata"), "orderId"),
				text(metadata, "orderId"));

		Payment matched = codiQrId == null ? null : payments.findFirstByCodiQrId(codiQrId).orElse(null);
		String orderId = matched != null ? matched.orderId() : fallbackOrderId;
		if (orderId == null) {
			log.warn("pey codi.qr.payment_received matched no payment (codiQrId={})", codiQrId);
			return;
		}
		markPaid(orderId, matched == null ? null : matched.id(), transactionId, now);
	}

	/**
	 * pending/expired -> paid with a conditional UPDATE: of N concurrent deliveries for one order exactly one gets
	 * rowCount 1 and applies the stock, so stock can never be taken twice. Products are processed in id order so two
	 * orders paid at once lock their products in the same order (no deadlock).
	 */
	private void markPaid(String orderId, String paymentId, String transactionId, long now) {
		if (orders.markPaid(orderId, now) == 0) {
			log.warn("pey payment for order {} ignored: unknown, already paid or cancelled", orderId);
			return;
		}
		if (paymentId != null) {
			if (transactionId != null) {
				payments.markPaid(paymentId, transactionId);
			}
			else {
				payments.markPaid(paymentId);
			}
		}
		else {
			var latest = payments.findFirstByOrderIdOrderByCreatedAtDescIdDesc(orderId);
			if (latest.isPresent()) {
				if (transactionId != null) {
					payments.markPaid(latest.get().id(), transactionId);
				}
				else {
					payments.markPaid(latest.get().id());
				}
			}
			else {
				long total = orders.findById(orderId).map(PurchaseOrder::totalCents).orElse(0L);
				payments.save(Payment.paidWithoutQr(orderId, transactionId, total, now));
			}
		}

		Map<String, Integer> qtyByProduct = new TreeMap<>();
		for (OrderItem item : items.findByOrderIdOrderByIdAsc(orderId)) {
			qtyByProduct.merge(item.productId(), item.qty(), Integer::sum);
		}
		qtyByProduct.forEach((productId, qty) -> stock.recordSale(productId, qty, now));
	}

	private void onBankAccountUpdated(JsonNode data) {
		String bankAccountId = firstText(data, "bankAccountId", "id");
		if (bankAccountId != null) {
			businesses.markCodiActive(bankAccountId);
		}
	}

	/** Node's {@code {...payload, ...payload.data}}: fields nested under {@code data} win over top-level ones. */
	private static JsonNode merged(ObjectNode payload) {
		JsonNode data = payload.get("data");
		if (data != null && data.isObject()) {
			ObjectNode copy = payload.deepCopy();
			copy.setAll((ObjectNode) data);
			return copy;
		}
		return payload;
	}

	private static String text(JsonNode node, String field) {
		JsonNode v = node.get(field);
		return v != null && v.isString() ? v.stringValue() : "";
	}

	private static String firstText(JsonNode node, String a, String b) {
		String first = text(node, a);
		if (!first.isEmpty()) {
			return first;
		}
		String second = text(node, b);
		return second.isEmpty() ? null : second;
	}

	private static String firstNonNull(String a, String b) {
		return !a.isEmpty() ? a : (!b.isEmpty() ? b : null);
	}

}
