package mx.paydmex.api.ai;

import java.time.Clock;
import java.time.ZoneId;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

import mx.paydmex.api.ai.ProductMatcher.Match;
import mx.paydmex.api.business.BusinessLookup.OwnBusiness;
import mx.paydmex.api.business.BusinessService;
import mx.paydmex.api.common.AppException;
import mx.paydmex.api.order.CreateOrderRequest;
import mx.paydmex.api.order.OrderDto;
import mx.paydmex.api.order.OrderService;
import mx.paydmex.api.order.SalesService;
import mx.paydmex.api.order.SalesSummaryDto;
import mx.paydmex.api.product.AdjustStockRequest;
import mx.paydmex.api.product.CreateProductRequest;
import mx.paydmex.api.product.ProductDto;
import mx.paydmex.api.product.ProductService;
import mx.paydmex.api.product.StockAdjustmentDto;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;
import tools.jackson.databind.node.ArrayNode;
import tools.jackson.databind.node.ObjectNode;

/**
 * Runs one tool call the model asked for. Every tool goes through the same services the REST routes use, as the
 * authenticated user, so authorization, stock rules and money rules are identical to the app's. No tool charges money:
 * {@code record_sale} / {@code reorder_last} only create {@code pending_payment} orders. Failures never throw: they come
 * back as an {@code "Error: ..."} string for the model to react to (ask the user, pick a candidate).
 */
@Component
class AiToolExecutor {

	private static final Logger log = LoggerFactory.getLogger(AiToolExecutor.class);

	/** CDMX has no DST since 2022, so "today" for a merchant starts at local midnight, not at UTC midnight. */
	static final ZoneId BUSINESS_ZONE = ZoneId.of("America/Mexico_City");

	private static final int LIST_LIMIT = 20;

	private static final int SEARCH_LIMIT = 5;

	private static final int DEFAULT_LOW_STOCK_THRESHOLD = 5;

	/** Bad tool arguments; becomes "Error de validacion en <tool>: <message>". */
	private static final class ArgsException extends RuntimeException {

		ArgsException(String message) {
			super(message);
		}

	}

	private record ProductView(String name, long priceCents, String display, Integer stock) {
	}

	private record LowStockView(String productId, String name, int stock, long priceCents, String display) {
	}

	private record TopView(String productId, String name, long qty, long revenueCents, String display) {
	}

	private record BusinessView(String id, String name, String category, String prepType) {
	}

	private final ProductService products;

	private final SalesService sales;

	private final OrderService orders;

	private final BusinessService businesses;

	private final JsonMapper json;

	private final Clock clock;

	AiToolExecutor(ProductService products, SalesService sales, OrderService orders, BusinessService businesses,
			JsonMapper json, Clock clock) {
		this.products = products;
		this.sales = sales;
		this.orders = orders;
		this.businesses = businesses;
		this.json = json;
		this.clock = clock;
	}

	static String display(long cents) {
		return String.format(Locale.ROOT, "$%d.%02d", cents / 100, Math.abs(cents % 100));
	}

	/** {@code business} null = the user is a customer. Actions performed are appended to {@code actions}. */
	String execute(String userId, OwnBusiness business, String tool, String rawArguments, List<AiAction> actions) {
		JsonNode args;
		try {
			args = rawArguments == null || rawArguments.isBlank() ? json.createObjectNode()
					: json.readTree(rawArguments);
		}
		catch (JacksonException ex) {
			return "Error: Argumentos JSON invalidos para la herramienta.";
		}
		try {
			if (args == null || !args.isObject()) {
				throw new ArgsException("argumentos invalidos");
			}
			return business != null ? ownerTool(userId, business, tool, args, actions) : customerTool(userId, tool, args, actions);
		}
		catch (ArgsException ex) {
			return "Error de validacion en " + tool + ": " + ex.getMessage();
		}
		catch (AppException ex) {
			return "Error: " + ex.getMessage();
		}
		catch (RuntimeException ex) {
			log.error("AI tool {} failed", tool, ex);
			return "Error al ejecutar la herramienta.";
		}
	}

	// ---- owner tools

	private String ownerTool(String userId, OwnBusiness business, String tool, JsonNode args, List<AiAction> actions) {
		return switch (tool) {
			case "list_products" -> listProducts(userId, args);
			case "record_sale" -> recordSale(userId, business, args, actions);
			case "adjust_stock" -> adjustStock(userId, args, actions);
			case "list_low_stock" -> listLowStock(userId, args);
			case "sales_summary" -> salesSummary(userId, args);
			case "create_product" -> createProduct(userId, args, actions);
			default -> "Error: Herramienta \"" + tool + "\" no disponible para dueno de negocio.";
		};
	}

	private String listProducts(String userId, JsonNode args) {
		String query = optionalText(args, "query");
		String normQuery = query == null ? "" : ProductMatcher.normalize(query);
		List<ProductView> views = products.listOwn(userId)
			.stream()
			.filter(ProductMatcher::isSellable)
			.filter(p -> normQuery.isEmpty() || ProductMatcher.matches(normQuery, p.name()))
			.limit(LIST_LIMIT)
			.map(p -> new ProductView(p.name(), p.priceCents(), display(p.priceCents()), p.trackStock() ? p.stock() : null))
			.toList();
		return json.writeValueAsString(Map.of("products", views));
	}

	private String recordSale(String userId, OwnBusiness business, JsonNode args, List<AiAction> actions) {
		JsonNode rawItems = args.get("items");
		if (rawItems == null || !rawItems.isArray() || rawItems.isEmpty()) {
			throw new ArgsException("items: debe ser una lista no vacia");
		}
		List<ProductDto> catalog = products.listOwn(userId);
		ObjectNode body = json.createObjectNode();
		ArrayNode lines = body.putArray("items");
		for (int i = 0; i < rawItems.size(); i++) {
			JsonNode item = rawItems.get(i);
			String name = requiredText(item, "productName");
			long qty = integer(item, "qty", 1);
			Match match = ProductMatcher.match(catalog, name);
			if (match.error() != null) {
				return match.error();
			}
			lines.addObject().put("productId", match.product().id()).put("qty", qty);
		}
		return createOrder(userId, business.id(), body, actions);
	}

	private String adjustStock(String userId, JsonNode args, List<AiAction> actions) {
		String name = requiredText(args, "productName");
		long delta = integer(args, "delta", Integer.MIN_VALUE);
		if (delta == 0) {
			throw new ArgsException("delta: no puede ser 0");
		}
		if (delta > Integer.MAX_VALUE) {
			throw new ArgsException("delta: fuera de rango");
		}
		String reason = requiredText(args, "reason");
		Match match = ProductMatcher.match(products.listOwn(userId), name);
		if (match.error() != null) {
			return match.error();
		}
		StockAdjustmentDto updated = products.adjustStock(userId, match.product().id(),
				new AdjustStockRequest((int) delta, reason));
		actions.add(AiAction.StockAdjusted.of(match.product().id(), updated.stock()));
		return json.writeValueAsString(
				Map.of("productId", match.product().id(), "name", match.product().name(), "newStock", updated.stock()));
	}

	private String listLowStock(String userId, JsonNode args) {
		long threshold = args.hasNonNull("threshold") ? integer(args, "threshold", 0) : DEFAULT_LOW_STOCK_THRESHOLD;
		List<LowStockView> views = products.lowStock(userId, (int) Math.min(threshold, Integer.MAX_VALUE))
			.stream()
			.map(p -> new LowStockView(p.id(), p.name(), p.stock(), p.priceCents(), display(p.priceCents())))
			.toList();
		return json.writeValueAsString(Map.of("products", views));
	}

	private String salesSummary(String userId, JsonNode args) {
		long now = clock.instant().getEpochSecond();
		long startOfToday = clock.instant().atZone(BUSINESS_ZONE).toLocalDate().atStartOfDay(BUSINESS_ZONE).toEpochSecond();
		long from = args.hasNonNull("from") ? integer(args, "from", Long.MIN_VALUE) : startOfToday;
		long to = args.hasNonNull("to") ? integer(args, "to", Long.MIN_VALUE) : now;
		SalesSummaryDto summary = sales.summary(userId, from, to);
		List<TopView> top = summary.topProducts()
			.stream()
			.map(p -> new TopView(p.productId(), p.name(), p.qty(), p.revenueCents(), display(p.revenueCents())))
			.toList();
		return json.writeValueAsString(Map.of("totalCents", summary.totalCents(), "display", display(summary.totalCents()),
				"orders", summary.orders(), "topProducts", top));
	}

	private String createProduct(String userId, JsonNode args, List<AiAction> actions) {
		String name = requiredText(args, "name");
		long price = integer(args, "priceCents", 1);
		boolean trackStock = true;
		if (args.hasNonNull("trackStock")) {
			if (!args.get("trackStock").isBoolean()) {
				throw new ArgsException("trackStock: debe ser booleano");
			}
			trackStock = args.get("trackStock").asBoolean();
		}
		long stock = args.hasNonNull("stock") ? integer(args, "stock", 0) : 0;
		if (stock > Integer.MAX_VALUE) {
			throw new ArgsException("stock: fuera de rango");
		}
		ProductDto created = products.create(userId,
				new CreateProductRequest(name, price, trackStock, (int) stock, null, null));
		actions.add(AiAction.ProductCreated.of(created.id()));
		return json.writeValueAsString(Map.of("productId", created.id(), "name", created.name(), "priceCents",
				created.priceCents(), "display", display(created.priceCents()), "trackStock", created.trackStock(), "stock",
				created.stock()));
	}

	// ---- customer tools

	private String customerTool(String userId, String tool, JsonNode args, List<AiAction> actions) {
		return switch (tool) {
			case "search_businesses" -> searchBusinesses(args);
			case "reorder_last" -> reorderLast(userId, args, actions);
			default -> "Error: Herramienta \"" + tool + "\" no permitida para clientes sin negocio.";
		};
	}

	private String searchBusinesses(JsonNode args) {
		String query = optionalText(args, "query");
		String category = optionalText(args, "category");
		if (category != null && !AiToolSpecs.CATEGORIES.contains(category)) {
			throw new ArgsException("category: valor invalido");
		}
		List<BusinessView> views = businesses.listActive(category, null, query)
			.stream()
			.limit(SEARCH_LIMIT)
			.map(b -> new BusinessView(b.id(), b.name(), b.category(), b.prepType()))
			.toList();
		return json.writeValueAsString(Map.of("businesses", views));
	}

	private String reorderLast(String userId, JsonNode args, List<AiAction> actions) {
		String businessId = optionalText(args, "businessId");
		OrderDto last = orders.list(userId, OrderService.Role.CUSTOMER, null)
			.stream()
			.filter(o -> businessId == null || o.businessId().equals(businessId))
			.findFirst()
			.orElse(null);
		if (last == null) {
			return "Error: No se encontro una orden anterior para repetir.";
		}
		Map<String, ProductDto> available = new HashMap<>();
		products.listActive(last.businessId()).forEach(p -> available.put(p.id(), p));

		ObjectNode body = json.createObjectNode();
		ArrayNode lines = body.putArray("items");
		for (OrderDto.ItemDto item : last.items()) {
			ProductDto p = available.get(item.productId());
			if (p == null || (p.trackStock() && p.stock() < item.qty())) {
				continue;
			}
			lines.addObject().put("productId", p.id()).put("qty", item.qty());
		}
		if (lines.isEmpty()) {
			return "Error: Ninguno de los productos de la ultima orden esta disponible actualmente.";
		}
		return createOrder(userId, last.businessId(), body, actions);
	}

	// ---- shared

	/** Goes through {@link CreateOrderRequest#parse} so the assistant gets the same line/qty limits as the API. */
	private String createOrder(String userId, String businessId, ObjectNode body, List<AiAction> actions) {
		body.put("businessId", businessId);
		OrderDto order = orders.create(userId, CreateOrderRequest.parse(body));
		actions.add(AiAction.OrderCreated.of(order.id(), order.totalCents()));
		return json.writeValueAsString(
				Map.of("orderId", order.id(), "totalCents", order.totalCents(), "display", display(order.totalCents())));
	}

	private static String optionalText(JsonNode args, String field) {
		JsonNode n = args.get(field);
		if (n == null || n.isNull()) {
			return null;
		}
		if (!n.isString()) {
			throw new ArgsException(field + ": debe ser texto");
		}
		String s = n.asString().trim();
		return s.isEmpty() ? null : s;
	}

	private static String requiredText(JsonNode args, String field) {
		JsonNode n = args == null ? null : args.get(field);
		if (n == null || !n.isString() || n.asString().isBlank()) {
			throw new ArgsException(field + ": es requerido");
		}
		return n.asString().trim();
	}

	/** Integral JSON number (2.0 is accepted, 2.5 is not) that fits a long and is {@code >= min}. */
	private static long integer(JsonNode args, String field, long min) {
		JsonNode n = args == null ? null : args.get(field);
		if (n == null || !n.isNumber()) {
			throw new ArgsException(field + ": debe ser un entero");
		}
		long value;
		if (n.isIntegralNumber() && n.canConvertToLong()) {
			value = n.longValue();
		}
		else if (n.isFloatingPointNumber() && n.doubleValue() == Math.rint(n.doubleValue())
				&& Math.abs(n.doubleValue()) < 9e15) {
			value = (long) n.doubleValue();
		}
		else {
			throw new ArgsException(field + ": debe ser un entero");
		}
		if (value < min) {
			throw new ArgsException(field + ": debe ser >= " + min);
		}
		return value;
	}

}
