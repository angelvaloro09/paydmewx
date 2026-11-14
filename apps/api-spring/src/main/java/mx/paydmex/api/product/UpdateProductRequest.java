package mx.paydmex.api.product;

import mx.paydmex.api.common.Patch;

import tools.jackson.databind.JsonNode;

/** PATCH /business/products/{id} body. Absent = keep; null clears only prepMinutes and imageUrl. */
public record UpdateProductRequest(Patch<String> name, Patch<Long> priceCents, Patch<Boolean> trackStock,
		Patch<Integer> stock, Patch<Integer> prepMinutes, Patch<String> imageUrl, Patch<Boolean> active) {

	public static UpdateProductRequest parse(JsonNode raw) {
		JsonNode body = ProductJson.object(raw);
		return new UpdateProductRequest(ProductJson.requiredText(body, "name"),
				ProductJson.nonNegativeLong(body, "priceCents"), ProductJson.flag(body, "trackStock"),
				ProductJson.nonNegativeInt(body, "stock"), ProductJson.nullablePositiveInt(body, "prepMinutes"),
				ProductJson.nullableText(body, "imageUrl"), ProductJson.flag(body, "active"));
	}

}
