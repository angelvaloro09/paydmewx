package mx.paydmex.api.order;

import java.util.ArrayList;
import java.util.List;

import mx.paydmex.api.common.AppException;

import org.springframework.http.HttpStatus;
import tools.jackson.databind.JsonNode;

/**
 * POST /orders body. Hand-parsed (like the product bodies) so a float qty is a 400 instead of being truncated.
 * Limits beyond the Node contract, to bound abuse: at most 100 lines, qty 1..10000, note up to 500 chars.
 */
public record CreateOrderRequest(String businessId, List<Line> items, String note) {

	static final int MAX_LINES = 100;

	static final int MAX_QTY = 10_000;

	static final int MAX_NOTE = 500;

	public record Line(String productId, int qty) {
	}

	public static CreateOrderRequest parse(JsonNode body) {
		if (body == null || !body.isObject()) {
			throw invalid("body: must be a JSON object");
		}
		String businessId = requiredText(body, "businessId", "businessId");
		JsonNode rawItems = body.get("items");
		if (rawItems == null || !rawItems.isArray() || rawItems.isEmpty()) {
			throw invalid("items: must be a non-empty array");
		}
		if (rawItems.size() > MAX_LINES) {
			throw invalid("items: at most " + MAX_LINES + " lines");
		}
		var lines = new ArrayList<Line>();
		for (int i = 0; i < rawItems.size(); i++) {
			JsonNode item = rawItems.get(i);
			String at = "items." + i;
			if (!item.isObject()) {
				throw invalid(at + ": must be an object");
			}
			String productId = requiredText(item, "productId", at + ".productId");
			JsonNode qty = item.get("qty");
			if (qty == null || !qty.isIntegralNumber() || !qty.canConvertToInt() || qty.intValue() < 1
					|| qty.intValue() > MAX_QTY) {
				throw invalid(at + ".qty: must be an integer between 1 and " + MAX_QTY);
			}
			lines.add(new Line(productId, qty.intValue()));
		}
		return new CreateOrderRequest(businessId, List.copyOf(lines), note(body));
	}

	private static String requiredText(JsonNode obj, String field, String label) {
		JsonNode n = obj.get(field);
		if (n == null || !n.isString() || n.stringValue().isBlank()) {
			throw invalid(label + ": is required");
		}
		return n.stringValue();
	}

	private static String note(JsonNode body) {
		JsonNode n = body.get("note");
		if (n == null || n.isNull()) {
			return null;
		}
		if (!n.isString()) {
			throw invalid("note: must be a string");
		}
		if (n.stringValue().length() > MAX_NOTE) {
			throw invalid("note: at most " + MAX_NOTE + " characters");
		}
		return n.stringValue();
	}

	private static AppException invalid(String message) {
		return new AppException(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", message);
	}

}
