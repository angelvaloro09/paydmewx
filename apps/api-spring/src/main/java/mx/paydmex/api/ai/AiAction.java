package mx.paydmex.api.ai;

/**
 * Side effect the assistant performed, reported to the app so it can refresh. {@code type} is a record component so
 * it serializes as a plain JSON property: {@code {"type":"order_created","orderId":...,"totalCents":...}}.
 */
public sealed interface AiAction {

	record OrderCreated(String type, String orderId, long totalCents) implements AiAction {

		static OrderCreated of(String orderId, long totalCents) {
			return new OrderCreated("order_created", orderId, totalCents);
		}

	}

	record StockAdjusted(String type, String productId, int newStock) implements AiAction {

		static StockAdjusted of(String productId, int newStock) {
			return new StockAdjusted("stock_adjusted", productId, newStock);
		}

	}

	record ProductCreated(String type, String productId) implements AiAction {

		static ProductCreated of(String productId) {
			return new ProductCreated("product_created", productId);
		}

	}

}
