package mx.paydmex.api.product;

import mx.paydmex.api.common.AppException;
import mx.paydmex.api.common.Patch;

import org.springframework.http.HttpStatus;
import tools.jackson.databind.JsonNode;

/**
 * Strict hand parsing of owner request bodies. A record cannot tell a missing key from an explicit null (the
 * contract needs null = clear for prepMinutes/imageUrl), and Jackson would silently truncate 10.5 to 10 for a long.
 * Every failure is a 400 VALIDATION_ERROR "field: message". Unknown keys are ignored.
 */
final class ProductJson {

	private ProductJson() {
	}

	static JsonNode object(JsonNode body) {
		if (body == null || !body.isObject()) {
			throw invalid("body: must be a JSON object");
		}
		return body;
	}

	static Patch<String> requiredText(JsonNode body, String field) {
		Patch<String> p = text(body, field);
		if (p.present() && p.value().isBlank()) {
			throw invalid(field + ": is required");
		}
		return p;
	}

	static Patch<String> nullableText(JsonNode body, String field) {
		if (body.has(field) && body.get(field).isNull()) {
			return Patch.of(null);
		}
		return text(body, field);
	}

	static Patch<Long> nonNegativeLong(JsonNode body, String field) {
		if (!body.has(field)) {
			return Patch.absent();
		}
		JsonNode n = body.get(field);
		if (!n.isIntegralNumber() || !n.canConvertToLong() || n.longValue() < 0) {
			throw invalid(field + ": must be a non-negative integer");
		}
		return Patch.of(n.longValue());
	}

	static Patch<Integer> nonNegativeInt(JsonNode body, String field) {
		if (!body.has(field)) {
			return Patch.absent();
		}
		JsonNode n = body.get(field);
		if (!n.isIntegralNumber() || !n.canConvertToInt() || n.intValue() < 0) {
			throw invalid(field + ": must be a non-negative integer");
		}
		return Patch.of(n.intValue());
	}

	static Patch<Integer> nullablePositiveInt(JsonNode body, String field) {
		if (!body.has(field)) {
			return Patch.absent();
		}
		JsonNode n = body.get(field);
		if (n.isNull()) {
			return Patch.of(null);
		}
		if (!n.isIntegralNumber() || !n.canConvertToInt() || n.intValue() <= 0) {
			throw invalid(field + ": must be a positive integer");
		}
		return Patch.of(n.intValue());
	}

	static Patch<Integer> integer(JsonNode body, String field) {
		if (!body.has(field)) {
			return Patch.absent();
		}
		JsonNode n = body.get(field);
		if (!n.isIntegralNumber() || !n.canConvertToInt()) {
			throw invalid(field + ": must be an integer");
		}
		return Patch.of(n.intValue());
	}

	static Patch<Boolean> flag(JsonNode body, String field) {
		if (!body.has(field)) {
			return Patch.absent();
		}
		JsonNode n = body.get(field);
		if (!n.isBoolean()) {
			throw invalid(field + ": must be a boolean");
		}
		return Patch.of(n.booleanValue());
	}

	static <T> T require(Patch<T> p, String field) {
		if (!p.present()) {
			throw invalid(field + ": is required");
		}
		return p.value();
	}

	private static Patch<String> text(JsonNode body, String field) {
		if (!body.has(field)) {
			return Patch.absent();
		}
		JsonNode n = body.get(field);
		if (!n.isString()) {
			throw invalid(field + ": must be a string");
		}
		return Patch.of(n.stringValue());
	}

	static AppException invalid(String message) {
		return new AppException(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", message);
	}

}
