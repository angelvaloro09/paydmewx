package mx.paydmex.api.ai;

import static mx.paydmex.api.ai.AiFixtures.message;
import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.List;

import mx.paydmex.api.ai.AiFixtures.Account;
import mx.paydmex.api.ai.AiFixtures.Merchant;
import mx.paydmex.api.ai.LlmClient.LlmMessage;
import mx.paydmex.api.common.AppException;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import tools.jackson.databind.JsonNode;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(FakeLlmClient.Config.class)
class AiAssistTests {

	private static final String TACO_SALE = "{\"items\":[{\"productName\":\"Taco al pastor\",\"qty\":2}]}";

	@Autowired
	MockMvc mvc;

	@Autowired
	JdbcTemplate jdbc;

	@Autowired
	FakeLlmClient llm;

	private AiFixtures fx;

	@BeforeEach
	void setUp() {
		fx = new AiFixtures(mvc, jdbc);
		llm.reset();
	}

	@AfterEach
	void cleanup() {
		fx.cleanup();
	}

	private Merchant taqueria(String label) throws Exception {
		Merchant m = fx.merchant(label);
		fx.product(m, "Taco al Pastor", 2500, true, 20);
		fx.product(m, "Agua de jamaica", 3500, true, 3);
		return m;
	}

	// ---- auth, limits, validation

	@Test
	void requiresAuthentication() throws Exception {
		fx.assist(null, message("Hola")).andExpect(status().isUnauthorized());
		assertThat(llm.calls).isEmpty();
	}

	@Test
	void rateLimitsTheTwentyFirstCallInAMinute() throws Exception {
		Account user = fx.customer("rate");
		llm.fallback = new LlmClient.LlmResponse("Respuesta breve", List.of());
		for (int i = 1; i <= 20; i++) {
			fx.assist(user.token(), message("Mensaje " + i)).andExpect(status().isOk());
		}
		fx.assist(user.token(), message("Mensaje 21"))
			.andExpect(status().isTooManyRequests())
			.andExpect(jsonPath("$.error.code").value("RATE_LIMITED"));
		assertThat(llm.calls).hasSize(20);
	}

	@Test
	void rateLimitIsPerUser() throws Exception {
		Account a = fx.customer("rate-a");
		Account b = fx.customer("rate-b");
		llm.fallback = new LlmClient.LlmResponse("ok", List.of());
		for (int i = 0; i < 20; i++) {
			fx.assist(a.token(), message("hola")).andExpect(status().isOk());
		}
		fx.assist(a.token(), message("hola")).andExpect(status().isTooManyRequests());
		fx.assist(b.token(), message("hola")).andExpect(status().isOk());
	}

	@Test
	void rejectsInvalidBodiesBeforeCallingTheModel() throws Exception {
		Account user = fx.customer("validation");
		fx.assist(user.token(), "{}")
			.andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.error.code").value("VALIDATION_ERROR"))
			.andExpect(jsonPath("$.error.message").value("message: is required"));
		fx.assist(user.token(), message("   "))
			.andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.error.message").value("message: must not be empty"));
		fx.assist(user.token(), message("x".repeat(1001)))
			.andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.error.message").value("message: at most 1000 characters"));
		fx.assist(user.token(), "{\"message\":\"hola\",\"history\":[{\"role\":\"system\",\"content\":\"x\"}]}")
			.andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.error.message").value("history.0.role: must be one of user, assistant"));
		String eleven = "{\"role\":\"user\",\"content\":\"x\"},".repeat(11);
		fx.assist(user.token(), "{\"message\":\"hola\",\"history\":[" + eleven.substring(0, eleven.length() - 1) + "]}")
			.andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.error.message").value("history: at most 10 items"));
		assertThat(llm.calls).isEmpty();
	}

	@Test
	void forwardsHistoryAndSystemPromptWithTheUsersRole() throws Exception {
		Merchant m = taqueria("history");
		llm.say("Hola");
		fx.assist(m.token(),
				"{\"message\":\"y ahora?\",\"history\":[{\"role\":\"user\",\"content\":\"hola\"},"
						+ "{\"role\":\"assistant\",\"content\":\"buenas\"}]}")
			.andExpect(status().isOk());

		List<LlmMessage> sent = llm.calls.getFirst().messages();
		assertThat(sent).hasSize(4);
		assertThat(sent.get(0)).isInstanceOf(LlmMessage.System.class);
		assertThat(((LlmMessage.System) sent.get(0)).content()).contains("owner (negocio: Tacos history)")
			.contains("Nunca cobras dinero");
		assertThat(sent.subList(1, 4)).containsExactly(new LlmMessage.User("hola"),
				new LlmMessage.Assistant("buenas", List.of()), new LlmMessage.User("y ahora?"));
	}

	@Test
	void upstreamFailureIsReportedWithoutDetails() throws Exception {
		Account user = fx.customer("upstream");
		llm.failure = new AppException(HttpStatus.BAD_GATEWAY, "LLM_ERROR", "No pudimos contactar al asistente");
		fx.assist(user.token(), message("hola"))
			.andExpect(status().isBadGateway())
			.andExpect(jsonPath("$.error.code").value("LLM_ERROR"))
			.andExpect(jsonPath("$.error.message").value("No pudimos contactar al asistente"));
	}

	@Test
	void replyIsPlainText() throws Exception {
		Account user = fx.customer("plain");
		llm.say("**Hola** `x` 😀 mundo  \nlinea");
		JsonNode body = fx.assistOk(user.token(), "hola");
		assertThat(body.get("reply").asString()).isEqualTo("Hola x  mundo\nlinea");
		assertThat(body.get("actions")).isEmpty();
	}

	// ---- owner tools

	@Test
	void recordSaleCreatesAPendingWalkInOrderAndReportsTheAction() throws Exception {
		Merchant m = taqueria("sale");
		llm.callTool("call_1", "record_sale", TACO_SALE).say("Listo, orden por $50.00 pendiente de cobro.");

		JsonNode body = fx.assistOk(m.token(), "Cobrame 2 tacos al pastor");

		assertThat(body.get("reply").asString()).isEqualTo("Listo, orden por $50.00 pendiente de cobro.");
		assertThat(body.get("actions")).hasSize(1);
		JsonNode action = body.get("actions").get(0);
		assertThat(action.get("type").asString()).isEqualTo("order_created");
		assertThat(action.get("totalCents").asLong()).isEqualTo(5000);

		String orderId = action.get("orderId").asString();
		assertThat(fx.jdbc.queryForObject("SELECT status FROM orders WHERE id = ?", String.class, orderId))
			.isEqualTo("pending_payment");
		assertThat(fx.jdbc.queryForObject("SELECT customer_id FROM orders WHERE id = ?", String.class, orderId))
			.isNull();
		assertThat(fx.count("SELECT total_cents FROM orders WHERE id = ?", orderId)).isEqualTo(5000);
		// the assistant never moves money or stock: stock is taken only by the payment webhook
		assertThat(fx.count("SELECT stock FROM products WHERE business_id = ? AND name = 'Taco al Pastor'",
				m.businessId()))
			.isEqualTo(20);

		JsonNode toolResult = fx.json.readTree(llm.toolOutput(1, 0));
		assertThat(toolResult.get("orderId").asString()).isEqualTo(orderId);
		assertThat(toolResult.get("totalCents").asLong()).isEqualTo(5000);
		assertThat(toolResult.get("display").asString()).isEqualTo("$50.00");
	}

	@Test
	void adjustStockChangesStockAndLogsAMovement() throws Exception {
		Merchant m = taqueria("adjust");
		llm.callTool("c1", "adjust_stock", "{\"productName\":\"taco al pastor\",\"delta\":5,\"reason\":\"restock\"}")
			.say("Stock actualizado a 25.");

		JsonNode body = fx.assistOk(m.token(), "Agrega 5 tacos");

		assertThat(body.get("actions")).hasSize(1);
		assertThat(body.get("actions").get(0).get("type").asString()).isEqualTo("stock_adjusted");
		assertThat(body.get("actions").get(0).get("newStock").asInt()).isEqualTo(25);
		assertThat(fx.count("SELECT stock FROM products WHERE id = ?", body.get("actions").get(0).get("productId").asString()))
			.isEqualTo(25);
		assertThat(fx.count("SELECT COUNT(*) FROM stock_movements WHERE reason = 'restock' AND delta = 5")).isEqualTo(1);
	}

	@Test
	void adjustStockBelowZeroIsAToolErrorNotAnHttpError() throws Exception {
		Merchant m = taqueria("adjust-neg");
		llm.callTool("c1", "adjust_stock", "{\"productName\":\"agua de jamaica\",\"delta\":-10,\"reason\":\"merma\"}")
			.say("No hay tanto stock.");

		JsonNode body = fx.assistOk(m.token(), "Quita 10 aguas");

		assertThat(body.get("actions")).isEmpty();
		assertThat(llm.toolOutput(1, 0)).startsWith("Error:").contains("negative");
		assertThat(fx.count("SELECT stock FROM products WHERE business_id = ? AND name = 'Agua de jamaica'",
				m.businessId()))
			.isEqualTo(3);
	}

	@Test
	void unknownProductListsCandidatesAndCreatesNothing() throws Exception {
		Merchant m = taqueria("unknown");
		llm.callTool("c1", "record_sale", "{\"items\":[{\"productName\":\"Torta de Tamal\",\"qty\":1}]}")
			.say("No encontre eso.");

		JsonNode body = fx.assistOk(m.token(), "Vende una torta");

		assertThat(body.get("actions")).isEmpty();
		assertThat(llm.toolOutput(1, 0)).startsWith("Error:").contains("Taco al Pastor").contains("Agua de jamaica");
		assertThat(fx.count("SELECT COUNT(*) FROM orders WHERE business_id = ?", m.businessId())).isZero();
	}

	@Test
	void matcherAcceptsPluralsAndRejectsAmbiguousNames() throws Exception {
		Merchant m = taqueria("matcher");
		llm.callTool("c1", "record_sale", "{\"items\":[{\"productName\":\"tacos\",\"qty\":2}]}").say("Orden creada.");
		JsonNode first = fx.assistOk(m.token(), "Vende 2 tacos");
		assertThat(first.get("actions")).hasSize(1);
		assertThat(first.get("actions").get(0).get("totalCents").asLong()).isEqualTo(5000);

		fx.product(m, "Taco de Suadero", 2800, true, 15);
		llm.reset();
		llm.callTool("c2", "record_sale", "{\"items\":[{\"productName\":\"tacos\",\"qty\":1}]}").say("Cual taco?");
		JsonNode ambiguous = fx.assistOk(m.token(), "Vende 1 taco");
		assertThat(ambiguous.get("actions")).isEmpty();
		assertThat(llm.toolOutput(1, 0)).contains("ambiguo").contains("Taco al Pastor").contains("Taco de Suadero");
		assertThat(fx.count("SELECT COUNT(*) FROM orders WHERE business_id = ?", m.businessId())).isEqualTo(1);
	}

	@Test
	void recordSaleRejectsMoreThanTheStockOnHand() throws Exception {
		Merchant m = taqueria("oversell");
		llm.callTool("c1", "record_sale", "{\"items\":[{\"productName\":\"agua\",\"qty\":4}]}").say("No alcanza.");

		JsonNode body = fx.assistOk(m.token(), "Vende 4 aguas");

		assertThat(body.get("actions")).isEmpty();
		assertThat(llm.toolOutput(1, 0)).startsWith("Error:").contains("Insufficient stock");
		assertThat(fx.count("SELECT COUNT(*) FROM orders WHERE business_id = ?", m.businessId())).isZero();
	}

	@Test
	void badToolArgumentsComeBackAsErrorsForTheModel() throws Exception {
		Merchant m = taqueria("badargs");
		llm.callTool("c1", "record_sale", "{not json").callTool("c2", "record_sale", "{\"items\":[]}")
			.callTool("c3", "record_sale", "{\"items\":[{\"productName\":\"taco\",\"qty\":0}]}")
			.say("Ups.");
		fx.assistOk(m.token(), "haz cosas raras");

		assertThat(llm.toolOutput(3, 0)).isEqualTo("Error: Argumentos JSON invalidos para la herramienta.");
		assertThat(llm.toolOutput(3, 1)).startsWith("Error de validacion en record_sale:");
		assertThat(llm.toolOutput(3, 2)).startsWith("Error de validacion en record_sale: qty");

		llm.reset();
		llm.callTool("c4", "adjust_stock", "{\"productName\":\"taco\",\"delta\":0,\"reason\":\"x\"}").say("Ups.");
		fx.assistOk(m.token(), "ajusta cero");
		assertThat(llm.toolOutput(1, 0)).isEqualTo("Error de validacion en adjust_stock: delta: no puede ser 0");
		assertThat(fx.count("SELECT COUNT(*) FROM orders WHERE business_id = ?", m.businessId())).isZero();
	}

	@Test
	void listProductsHidesQuickChargeAndShowsNullStockWhenUntracked() throws Exception {
		Merchant m = taqueria("list");
		fx.product(m, "Cobro rapido", 100, false, 0);
		fx.product(m, "Salsa extra", 1000, false, 99);
		llm.callTool("c1", "list_products", "{}").say("Tienes tacos, agua y salsa.");

		fx.assistOk(m.token(), "Que productos tengo?");

		JsonNode products = fx.json.readTree(llm.toolOutput(1, 0)).get("products");
		assertThat(products).hasSize(3);
		assertThat(products.get(0).get("name").asString()).isEqualTo("Taco al Pastor");
		assertThat(products.get(0).get("display").asString()).isEqualTo("$25.00");
		assertThat(products.get(0).get("stock").asInt()).isEqualTo(20);
		assertThat(products.get(2).get("name").asString()).isEqualTo("Salsa extra");
		assertThat(products.get(2).get("stock").isNull()).isTrue();
		assertThat(llm.toolOutput(1, 0)).doesNotContain("Cobro");
	}

	@Test
	void listLowStockSalesSummaryAndCreateProduct() throws Exception {
		Merchant m = taqueria("misc");
		llm.callTool("c1", "list_low_stock", "{\"threshold\":5}")
			.callTool("c2", "sales_summary", "{}")
			.callTool("c3", "create_product", "{\"name\":\"Quesadilla\",\"priceCents\":4500,\"stock\":8}")
			.say("Hecho.");

		JsonNode body = fx.assistOk(m.token(), "Resumen y crea quesadilla");

		JsonNode low = fx.json.readTree(llm.toolOutput(3, 0)).get("products");
		assertThat(low).hasSize(1);
		assertThat(low.get(0).get("name").asString()).isEqualTo("Agua de jamaica");
		JsonNode summary = fx.json.readTree(llm.toolOutput(3, 1));
		assertThat(summary.get("totalCents").asLong()).isZero();
		assertThat(summary.get("display").asString()).isEqualTo("$0.00");
		assertThat(summary.get("orders").asLong()).isZero();

		assertThat(body.get("actions")).hasSize(1);
		assertThat(body.get("actions").get(0).get("type").asString()).isEqualTo("product_created");
		assertThat(fx.count("SELECT stock FROM products WHERE business_id = ? AND name = 'Quesadilla'", m.businessId()))
			.isEqualTo(8);
	}

	@Test
	void stopsAfterFourToolRoundsAndAnswersWithTheLastText() throws Exception {
		Merchant m = taqueria("loop");
		for (int i = 1; i <= 4; i++) {
			llm.script("Paso " + i, "loop_" + i, "list_low_stock", "{\"threshold\":5}");
		}

		JsonNode body = fx.assistOk(m.token(), "revisa en bucle");

		assertThat(llm.calls).hasSize(AiService.MAX_TOOL_ROUNDS);
		assertThat(body.get("reply").asString()).isEqualTo("Paso 4");
	}

	// ---- customer tools

	@Test
	void customerIsOfferedOnlyCustomerToolsAndCannotInvokeOwnerOnes() throws Exception {
		Merchant m = taqueria("cust-tools");
		Account customer = fx.customer("cust-tools-buyer");
		llm.callTool("c1", "record_sale", TACO_SALE).say("Solo puedes buscar negocios.");

		JsonNode body = fx.assistOk(customer.token(), "Registra una venta");

		assertThat(body.get("actions")).isEmpty();
		assertThat(llm.calls.getFirst().tools().stream().map(LlmClient.LlmTool::name).toList())
			.containsExactly("search_businesses", "reorder_last");
		assertThat(llm.toolOutput(1, 0)).startsWith("Error:").contains("no permitida");
		assertThat(fx.count("SELECT COUNT(*) FROM orders WHERE business_id = ?", m.businessId())).isZero();
	}

	@Test
	void ownerIsOfferedOnlyOwnerTools() throws Exception {
		Merchant m = taqueria("owner-tools");
		llm.say("ok");
		fx.assistOk(m.token(), "hola");
		assertThat(llm.calls.getFirst().tools().stream().map(LlmClient.LlmTool::name).toList())
			.containsExactly("list_products", "record_sale", "adjust_stock", "list_low_stock", "sales_summary",
					"create_product");
	}

	@Test
	void searchBusinessesFindsActiveBusinessesByTextAndCategory() throws Exception {
		taqueria("search");
		Account customer = fx.customer("search-buyer");
		llm.callTool("c1", "search_businesses", "{\"query\":\"Tacos search\",\"category\":\"food\"}")
			.callTool("c2", "search_businesses", "{\"category\":\"spaceships\"}")
			.say("Encontre uno.");

		fx.assistOk(customer.token(), "Donde hay tacos?");

		JsonNode found = fx.json.readTree(llm.toolOutput(2, 0)).get("businesses");
		assertThat(found).hasSize(1);
		assertThat(found.get(0).get("name").asString()).isEqualTo("Tacos search");
		assertThat(found.get(0).get("prepType").asString()).isEqualTo("instant");
		assertThat(llm.toolOutput(2, 1)).startsWith("Error de validacion en search_businesses: category");
	}

	@Test
	void reorderLastCopiesTheAvailableItemsOfTheLastOrder() throws Exception {
		Merchant m = taqueria("reorder");
		Account customer = fx.customer("reorder-buyer");
		String taco = fx.jdbc.queryForObject("SELECT id FROM products WHERE business_id = ? AND name = 'Taco al Pastor'",
				String.class, m.businessId());
		fx.mvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post("/orders")
			.header("Authorization", "Bearer " + customer.token())
			.contentType(org.springframework.http.MediaType.APPLICATION_JSON)
			.content("{\"businessId\":\"" + m.businessId() + "\",\"items\":[{\"productId\":\"" + taco + "\",\"qty\":2}]}"))
			.andExpect(status().isCreated());
		llm.callTool("c1", "reorder_last", "{}").say("Repeti tu ultimo pedido.");

		JsonNode body = fx.assistOk(customer.token(), "Repite mi ultimo pedido");

		assertThat(body.get("actions")).hasSize(1);
		assertThat(body.get("actions").get(0).get("type").asString()).isEqualTo("order_created");
		assertThat(body.get("actions").get(0).get("totalCents").asLong()).isEqualTo(5000);
		assertThat(fx.count("SELECT COUNT(*) FROM orders WHERE customer_id = ?", customer.id())).isEqualTo(2);
	}

	@Test
	void reorderLastWithoutHistoryOrWithNothingAvailableIsAToolError() throws Exception {
		Merchant m = taqueria("reorder-none");
		Account customer = fx.customer("reorder-none-buyer");
		llm.callTool("c1", "reorder_last", "{}").say("No tienes pedidos.");
		fx.assistOk(customer.token(), "Repite mi ultimo pedido");
		assertThat(llm.toolOutput(1, 0)).isEqualTo("Error: No se encontro una orden anterior para repetir.");

		String agua = fx.jdbc.queryForObject("SELECT id FROM products WHERE business_id = ? AND name = 'Agua de jamaica'",
				String.class, m.businessId());
		fx.mvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post("/orders")
			.header("Authorization", "Bearer " + customer.token())
			.contentType(org.springframework.http.MediaType.APPLICATION_JSON)
			.content("{\"businessId\":\"" + m.businessId() + "\",\"items\":[{\"productId\":\"" + agua + "\",\"qty\":3}]}"))
			.andExpect(status().isCreated());
		fx.jdbc.update("UPDATE products SET stock = 0 WHERE id = ?", agua);
		llm.reset();
		llm.callTool("c2", "reorder_last", "{}").say("No hay disponibles.");
		JsonNode body = fx.assistOk(customer.token(), "Repite");

		assertThat(body.get("actions")).isEmpty();
		assertThat(llm.toolOutput(1, 0)).startsWith("Error: Ninguno de los productos");
		assertThat(fx.count("SELECT COUNT(*) FROM orders WHERE customer_id = ?", customer.id())).isEqualTo(1);
	}

}
