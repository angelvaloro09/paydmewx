package mx.paydmex.api.order;

import java.util.List;

/**
 * Order as the Node API returns it: the row's camelCase columns plus {@code items} and the latest {@code payment}
 * (null when none). Money is long centavos, times are unix seconds.
 */
public record OrderDto(String id, String businessId, String customerId, String status, long totalCents, String note,
		long createdAt, Long paidAt, List<ItemDto> items, PaymentDto payment) {

	public record ItemDto(String id, String orderId, String productId, String name, long priceCents, int qty) {

		static ItemDto from(OrderItem i) {
			return new ItemDto(i.id(), i.orderId(), i.productId(), i.name(), i.priceCents(), i.qty());
		}

	}

	public record PaymentDto(String id, String orderId, String codiQrId, String qrString, Long expiresAt,
			String transactionId, String status, long amountCents, long createdAt) {

		static PaymentDto from(Payment p) {
			return new PaymentDto(p.id(), p.orderId(), p.codiQrId(), p.qrString(), p.expiresAt(), p.transactionId(),
					p.status(), p.amountCents(), p.createdAt());
		}

	}

	static OrderDto of(PurchaseOrder o, List<OrderItem> items, Payment latestPayment) {
		return new OrderDto(o.id(), o.businessId(), o.customerId(), o.status(), o.totalCents(), o.note(),
				o.createdAt(), o.paidAt(), items.stream().map(ItemDto::from).toList(),
				latestPayment == null ? null : PaymentDto.from(latestPayment));
	}

}
