package mx.paydmex.api.product;

import java.util.Collection;
import java.util.List;

import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/** Read-only view of the catalog for the order flow: price/name snapshot plus the stock to pre-check. */
@Component
public class ProductLookup {

	/** What an order needs from a product. Money is centavos. */
	public record ProductSnapshot(String id, String name, long priceCents, boolean trackStock, int stock) {
	}

	private final ProductRepository products;

	ProductLookup(ProductRepository products) {
		this.products = products;
	}

	/** Active products of one business among {@code ids}; ids that do not match are simply absent. */
	@Transactional(readOnly = true)
	public List<ProductSnapshot> findActive(String businessId, Collection<String> ids) {
		return products.findByBusinessIdAndActiveTrueAndIdIn(businessId, ids)
			.stream()
			.map(p -> new ProductSnapshot(p.id(), p.name(), p.priceCents(), p.trackStock(), p.stock()))
			.toList();
	}

}
