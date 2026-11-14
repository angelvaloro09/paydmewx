package mx.paydmex.api.order;

import java.util.ArrayList;
import java.util.List;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/**
 * Read-only aggregates over orders/order_items for the owner dashboard. Plain SQL on purpose: Phase 5 owns the
 * order entities, and these are projections that never write. Only orders that were actually paid count.
 */
@Repository
class SalesSummaryRepository {

	private static final String PAID = "o.status IN ('paid', 'preparing', 'ready', 'delivered')";

	record Totals(long orders, long totalCents) {
	}

	/** One row per (product, name as printed on the order): a renamed product appears once per name. */
	record ProductRow(String productId, String name, long qty, long revenueCents, long lastOrderAt) {
	}

	private final JdbcClient jdbc;

	SalesSummaryRepository(JdbcClient jdbc) {
		this.jdbc = jdbc;
	}

	Totals totals(String businessId, Long from, Long to) {
		var args = new ArrayList<Object>();
		String where = where(businessId, from, to, args);
		return jdbc.sql("SELECT COUNT(*), COALESCE(SUM(o.total_cents), 0) FROM orders o WHERE " + where)
			.params(args)
			.query((rs, i) -> new Totals(rs.getLong(1), rs.getLong(2)))
			.single();
	}

	List<ProductRow> productRows(String businessId, Long from, Long to) {
		var args = new ArrayList<Object>();
		String where = where(businessId, from, to, args);
		return jdbc.sql("""
				SELECT oi.product_id, oi.name, SUM(oi.qty), SUM(oi.price_cents * oi.qty), MAX(o.created_at)
				FROM order_items oi JOIN orders o ON o.id = oi.order_id
				WHERE\s""" + where + " GROUP BY oi.product_id, oi.name")
			.params(args)
			.query((rs, i) -> new ProductRow(rs.getString(1), rs.getString(2), rs.getLong(3), rs.getLong(4),
					rs.getLong(5)))
			.list();
	}

	/** Builds the WHERE with positional args; bounds are inclusive, like the Node API (gte/lte). */
	private static String where(String businessId, Long from, Long to, List<Object> args) {
		var sql = new StringBuilder("o.business_id = ? AND ").append(PAID);
		args.add(businessId);
		if (from != null) {
			sql.append(" AND o.created_at >= ?");
			args.add(from);
		}
		if (to != null) {
			sql.append(" AND o.created_at <= ?");
			args.add(to);
		}
		return sql.toString();
	}

}
