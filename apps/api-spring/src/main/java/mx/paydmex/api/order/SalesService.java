package mx.paydmex.api.order;

import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import mx.paydmex.api.business.OwnerBusinessResolver;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class SalesService {

	private static final int TOP_PRODUCTS = 10;

	private final SalesSummaryRepository repository;

	private final OwnerBusinessResolver owners;

	SalesService(SalesSummaryRepository repository, OwnerBusinessResolver owners) {
		this.repository = repository;
		this.owners = owners;
	}

	/**
	 * Paid orders (paid, preparing, ready, delivered) of the caller's business in [from, to] by created_at (unix
	 * seconds, both optional and inclusive). Top 10 products by qty, then revenue, then id. A product renamed
	 * between orders is merged under its most recent name.
	 */
	@Transactional(readOnly = true)
	public SalesSummaryDto summary(String userId, Long from, Long to) {
		String businessId = owners.requireBusinessId(userId);
		SalesSummaryRepository.Totals totals = repository.totals(businessId, from, to);
		if (totals.orders() == 0) {
			return new SalesSummaryDto(0, 0, List.of());
		}
		Map<String, Agg> byProduct = new LinkedHashMap<>();
		for (SalesSummaryRepository.ProductRow row : repository.productRows(businessId, from, to)) {
			byProduct.computeIfAbsent(row.productId(), Agg::new).add(row);
		}
		List<SalesSummaryDto.TopProduct> top = byProduct.values()
			.stream()
			.sorted(Comparator.comparingLong((Agg a) -> a.qty)
				.reversed()
				.thenComparing(Comparator.comparingLong((Agg a) -> a.revenueCents).reversed())
				.thenComparing(a -> a.productId))
			.limit(TOP_PRODUCTS)
			.map(a -> new SalesSummaryDto.TopProduct(a.productId, a.name, a.qty, a.revenueCents))
			.toList();
		return new SalesSummaryDto(totals.totalCents(), totals.orders(), top);
	}

	private static final class Agg {

		final String productId;

		String name;

		long qty;

		long revenueCents;

		long nameSeenAt = Long.MIN_VALUE;

		Agg(String productId) {
			this.productId = productId;
		}

		void add(SalesSummaryRepository.ProductRow row) {
			qty += row.qty();
			revenueCents += row.revenueCents();
			if (row.lastOrderAt() > nameSeenAt) {
				nameSeenAt = row.lastOrderAt();
				name = row.name();
			}
		}

	}

}
