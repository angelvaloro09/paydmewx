package mx.paydmex.api.product;

/**
 * Response of POST /business/products/{id}/stock. Same shape as the Node API: the product fields spread at the top
 * level (what the app reads) plus the nested {@code product} and {@code movement}.
 */
public record StockAdjustmentDto(String id, String businessId, String name, long priceCents, boolean trackStock,
		int stock, Integer prepMinutes, String imageUrl, boolean active, long createdAt, ProductDto product,
		StockMovementDto movement) {

	static StockAdjustmentDto of(ProductDto p, StockMovementDto movement) {
		return new StockAdjustmentDto(p.id(), p.businessId(), p.name(), p.priceCents(), p.trackStock(), p.stock(),
				p.prepMinutes(), p.imageUrl(), p.active(), p.createdAt(), p, movement);
	}

}
