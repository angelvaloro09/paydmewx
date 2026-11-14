package mx.paydmex.api.product;

public record StockMovementDto(String id, String productId, int delta, String reason, long createdAt) {

	static StockMovementDto from(StockMovement m) {
		return new StockMovementDto(m.id(), m.productId(), m.delta(), m.reason(), m.createdAt());
	}

}
