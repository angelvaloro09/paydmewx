package mx.paydmex.api.order;

import java.util.List;

/** GET /business/sales/summary. Money is long centavos; {@code orders} is the count of paid orders. */
public record SalesSummaryDto(long totalCents, long orders, List<TopProduct> topProducts) {

	public record TopProduct(String productId, String name, long qty, long revenueCents) {
	}

}
