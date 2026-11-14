package mx.paydmex.api.business;

import java.util.Set;

import mx.paydmex.api.common.AppException;

import org.springframework.http.HttpStatus;
import tools.jackson.databind.JsonNode;

/**
 * Partial update body. Parsed by hand from the JSON tree because a record cannot tell a missing key from an
 * explicit null, and the contract needs that (null clears description/address/lat/lng). Unknown keys are ignored.
 */
public record UpdateBusinessRequest(Patch<String> name, Patch<String> category, Patch<String> prepType,
		Patch<String> description, Patch<String> address, Patch<Double> lat, Patch<Double> lng,
		Patch<Boolean> active, Patch<String> clabe) {

	public static UpdateBusinessRequest parse(JsonNode body) {
		if (body == null || !body.isObject()) {
			throw invalid("body: must be a JSON object");
		}
		return new UpdateBusinessRequest(
				required(body, "name"),
				enumValue(body, "category", BusinessTaxonomy.CATEGORIES, BusinessTaxonomy.CATEGORY_MESSAGE),
				enumValue(body, "prepType", BusinessTaxonomy.PREP_TYPES, BusinessTaxonomy.PREP_TYPE_MESSAGE),
				nullableText(body, "description"),
				nullableText(body, "address"),
				coordinate(body, "lat", 90),
				coordinate(body, "lng", 180),
				flag(body, "active"),
				text(body, "clabe"));
	}

	private static Patch<String> required(JsonNode body, String field) {
		Patch<String> p = text(body, field);
		if (p.present() && p.value().isBlank()) {
			throw invalid(field + ": is required");
		}
		return p;
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

	private static Patch<String> nullableText(JsonNode body, String field) {
		if (body.has(field) && body.get(field).isNull()) {
			return Patch.of(null);
		}
		return text(body, field);
	}

	private static Patch<String> enumValue(JsonNode body, String field, Set<String> allowed, String message) {
		Patch<String> p = text(body, field);
		if (p.present() && !allowed.contains(p.value())) {
			throw invalid(field + ": " + message);
		}
		return p;
	}

	private static Patch<Double> coordinate(JsonNode body, String field, int limit) {
		if (!body.has(field)) {
			return Patch.absent();
		}
		JsonNode n = body.get(field);
		if (n.isNull()) {
			return Patch.of(null);
		}
		if (!n.isNumber()) {
			throw invalid(field + ": must be a number");
		}
		double v = n.doubleValue();
		if (Math.abs(v) > limit) {
			throw invalid(field + ": must be between -" + limit + " and " + limit);
		}
		return Patch.of(v);
	}

	private static Patch<Boolean> flag(JsonNode body, String field) {
		if (!body.has(field)) {
			return Patch.absent();
		}
		JsonNode n = body.get(field);
		if (!n.isBoolean()) {
			throw invalid(field + ": must be a boolean");
		}
		return Patch.of(n.booleanValue());
	}

	private static AppException invalid(String message) {
		return new AppException(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", message);
	}

}
