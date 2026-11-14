package mx.paydmex.api.product;

/** Product row as the Node API returns it. Money is long centavos. */
public record ProductDto(String id, String businessId, String name, long priceCents, boolean trackStock,
		int stock, Integer prepMinutes, String imageUrl, boolean active, long createdAt) {

	static ProductDto from(Product p) {
		return new ProductDto(p.id(), p.businessId(), p.name(), p.priceCents(), p.trackStock(), p.stock(),
				p.prepMinutes(), p.imageUrl(), p.active(), p.createdAt());
	}

}
