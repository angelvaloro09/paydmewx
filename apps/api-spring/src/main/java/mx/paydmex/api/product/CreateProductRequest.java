package mx.paydmex.api.product;

import mx.paydmex.api.common.Patch;

import tools.jackson.databind.JsonNode;

/** POST /business/products body with defaults applied: trackStock=true, stock=0, optional fields null. */
public record CreateProductRequest(String name, long priceCents, boolean trackStock, int stock, Integer prepMinutes,
		String imageUrl) {

	public static CreateProductRequest parse(JsonNode raw) {
		JsonNode body = ProductJson.object(raw);
		String name = ProductJson.require(ProductJson.requiredText(body, "name"), "name");
		long price = ProductJson.require(ProductJson.nonNegativeLong(body, "priceCents"), "priceCents");
		Patch<Boolean> track = ProductJson.flag(body, "trackStock");
		Patch<Integer> stock = ProductJson.nonNegativeInt(body, "stock");
		Patch<Integer> prep = ProductJson.nullablePositiveInt(body, "prepMinutes");
		Patch<String> image = ProductJson.nullableText(body, "imageUrl");
		return new CreateProductRequest(name, price, track.present() ? track.value() : true,
				stock.present() ? stock.value() : 0, prep.present() ? prep.value() : null,
				image.present() ? image.value() : null);
	}

}
