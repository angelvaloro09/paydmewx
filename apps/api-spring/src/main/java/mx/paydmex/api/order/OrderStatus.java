package mx.paydmex.api.order;

import java.util.Optional;

/** Wire values of {@code orders.status} (also the DB CHECK constraint). The entity stores the wire string. */
enum OrderStatus {

	PENDING_PAYMENT("pending_payment"), PAID("paid"), PREPARING("preparing"), READY("ready"), DELIVERED("delivered"),
	CANCELLED("cancelled"), EXPIRED("expired");

	private final String wire;

	OrderStatus(String wire) {
		this.wire = wire;
	}

	String wire() {
		return wire;
	}

	static Optional<OrderStatus> fromWire(String raw) {
		for (OrderStatus s : values()) {
			if (s.wire.equals(raw)) {
				return Optional.of(s);
			}
		}
		return Optional.empty();
	}

}
