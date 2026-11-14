package mx.paydmex.api.product;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * Stock writes that other features (orders) need, so they never touch {@link Product} internals. Every method must
 * run inside the caller's transaction: the stock change and its {@code stock_movements} row commit together.
 */
@Component
public class StockLedger {

	public static final String SALE_REASON = "sale";

	private static final Logger log = LoggerFactory.getLogger(StockLedger.class);

	private final ProductRepository products;

	private final StockMovementRepository movements;

	StockLedger(ProductRepository products, StockMovementRepository movements) {
		this.products = products;
		this.movements = movements;
	}

	/**
	 * Takes {@code qty} units out of a tracked product with {@code UPDATE ... WHERE stock >= :qty} and logs a
	 * {@code sale} movement. Untracked products are ignored. The money is already collected when this runs (webhook), so
	 * a product that sold out in the meantime is clamped to 0 under a row lock (the movement logs the units really
	 * taken) instead of failing the payment.
	 */
	public void recordSale(String productId, int qty, long nowSeconds) {
		if (products.decrementIfEnough(productId, qty) == 1) {
			movements.save(StockMovement.create(productId, -qty, SALE_REASON, nowSeconds));
			return;
		}
		Product p = products.lockById(productId).orElse(null);
		if (p == null || !p.trackStock() || p.stock() <= 0) {
			return;
		}
		int taken = p.stock();
		log.warn("Oversold product {}: sale of {} but only {} in stock; clamped to 0", productId, qty, taken);
		p.setStock(0);
		movements.save(StockMovement.create(productId, -taken, SALE_REASON, nowSeconds));
	}

}
