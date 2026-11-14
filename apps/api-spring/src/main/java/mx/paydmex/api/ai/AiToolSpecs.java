package mx.paydmex.api.ai;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import mx.paydmex.api.ai.LlmClient.LlmTool;

/** Tool catalogue offered to the model. Owners and customers get disjoint sets; the executor enforces it again. */
final class AiToolSpecs {

	static final List<String> CATEGORIES = List.of("food", "tailoring", "footwear", "clothing", "department", "grocery",
			"services", "other");

	static final List<LlmTool> OWNER = List.of(
			tool("list_products", "Lista productos activos con precio e inventario (max 20).",
					Map.of("query", string()), List.of()),
			tool("record_sale",
					"Registra una venta en mostrador creando una orden pendiente de pago (pending_payment). Nunca cobra dinero.",
					Map.of("items", Map.of("type", "array", "items", object(
							Map.of("productName", string(), "qty", Map.of("type", "integer", "minimum", 1)),
							List.of("productName", "qty")))),
					List.of("items")),
			tool("adjust_stock", "Ajusta el inventario de un producto del negocio.",
					Map.of("productName", string(), "delta", Map.of("type", "integer"), "reason", string()),
					List.of("productName", "delta", "reason")),
			tool("list_low_stock", "Lista los productos activos con bajo inventario.",
					Map.of("threshold", Map.of("type", "integer", "minimum", 0)), List.of()),
			tool("sales_summary", "Obtiene el resumen de ventas pagadas en un rango de tiempo (segundos unix).",
					Map.of("from", Map.of("type", "integer"), "to", Map.of("type", "integer")), List.of()),
			tool("create_product", "Crea un nuevo producto en el catalogo del negocio (precio en centavos).",
					Map.of("name", string(), "priceCents", Map.of("type", "integer", "minimum", 1), "trackStock",
							Map.of("type", "boolean"), "stock", Map.of("type", "integer", "minimum", 0)),
					List.of("name", "priceCents")));

	static final List<LlmTool> CUSTOMER = List.of(
			tool("search_businesses", "Busca negocios activos por texto o categoria (maximo 5).",
					Map.of("query", string(), "category", Map.of("type", "string", "enum", CATEGORIES)), List.of()),
			tool("reorder_last",
					"Crea una orden pendiente de pago copiando los productos disponibles de la ultima orden del cliente.",
					Map.of("businessId", string()), List.of()));

	private AiToolSpecs() {
	}

	private static Map<String, Object> string() {
		return Map.of("type", "string");
	}

	private static Map<String, Object> object(Map<String, Object> properties, List<String> required) {
		var schema = new LinkedHashMap<String, Object>();
		schema.put("type", "object");
		schema.put("properties", properties);
		if (!required.isEmpty()) {
			schema.put("required", required);
		}
		return schema;
	}

	private static LlmTool tool(String name, String description, Map<String, Object> properties,
			List<String> required) {
		return new LlmTool(name, description, object(properties, required));
	}

}
