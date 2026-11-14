package mx.paydmex.api.product;

import tools.jackson.databind.JsonNode;

/** POST /business/products/{id}/stock body. {@code reason} is stored trimmed. */
public record AdjustStockRequest(int delta, String reason) {

	public static AdjustStockRequest parse(JsonNode raw) {
		JsonNode body = ProductJson.object(raw);
		int delta = ProductJson.require(ProductJson.integer(body, "delta"), "delta");
		String reason = ProductJson.require(ProductJson.requiredText(body, "reason"), "reason");
		return new AdjustStockRequest(delta, reason.trim());
	}

}
