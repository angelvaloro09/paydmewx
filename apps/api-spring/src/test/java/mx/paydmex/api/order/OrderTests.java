package mx.paydmex.api.order;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;

import mx.paydmex.api.common.AppException;
import mx.paydmex.api.order.OrderFixtures.Account;
import mx.paydmex.api.order.OrderFixtures.Merchant;
import mx.paydmex.api.pey.FakePeyClient;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import tools.jackson.databind.JsonNode;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(FakePeyClient.Config.class)
class OrderTests {

	private static final String ULID = "[0-9A-HJKMNP-TV-Z]{26}";

	@Autowired
	MockMvc mvc;

	@Autowired
	JdbcTemplate jdbc;

	@Autowired
	FakePeyClient pey;

	private OrderFixtures fx;

	@BeforeEach
	void setUp() {
		fx = new OrderFixtures(mvc, jdbc);
		pey.reset();
	}

	@AfterEach
	void cleanup() {
		fx.cleanup();
	}

	// ---- POST /orders

	@Test
	void customerCreatesAPendingOrderWithPriceSnapshotAndNoStockTaken() throws Exception {
		Merchant m = fx.merchant("create-m");
		Account c = fx.customer("create-c");
		String taco = fx.product(m, "Taco", 1500, true, 10);
		String agua = fx.product(m, "Agua", 2500, false, 0);
		long before = Instant.now().getEpochSecond();

		mvc.perform(auth(post("/orders"), c.token()).contentType(MediaType.APPLICATION_JSON)
			.content("{\"businessId\":\"" + m.businessId() + "\",\"note\":\"sin cebolla\",\"items\":[{\"productId\":\""
					+ taco + "\",\"qty\":2},{\"productId\":\"" + agua + "\",\"qty\":1}]}"))
			.andExpect(status().isCreated())
			.andExpect(jsonPath("$.id").value(org.hamcrest.Matchers.matchesPattern(ULID)))
			.andExpect(jsonPath("$.businessId").value(m.businessId()))
			.andExpect(jsonPath("$.customerId").value(c.id()))
			.andExpect(jsonPath("$.status").value("pending_payment"))
			.andExpect(jsonPath("$.totalCents").value(5500))
			.andExpect(jsonPath("$.note").value("sin cebolla"))
			.andExpect(jsonPath("$.createdAt").value(org.hamcrest.Matchers.greaterThanOrEqualTo((int) before)))
			.andExpect(jsonPath("$.paidAt").doesNotExist())
			.andExpect(jsonPath("$.payment").doesNotExist())
			.andExpect(jsonPath("$.items.length()").value(2))
			.andExpect(jsonPath("$.items[0].productId").value(taco))
			.andExpect(jsonPath("$.items[0].name").value("Taco"))
			.andExpect(jsonPath("$.items[0].priceCents").value(1500))
			.andExpect(jsonPath("$.items[0].qty").value(2))
			.andExpect(jsonPath("$.items[1].productId").value(agua));

		assertThat(fx.stockOf(taco)).isEqualTo(10);
		assertThat(fx.count("SELECT COUNT(*) FROM stock_movements WHERE product_id = ?", taco)).isZero();
	}

	@Test
	void itemsKeepTheNameAndPriceOfTheMomentTheOrderWasPlaced() throws Exception {
		Merchant m = fx.merchant("snap-m");
		Account c = fx.customer("snap-c");
		String taco = fx.product(m, "Taco", 1500, true, 10);
		String orderId = fx.createOrder(c.token(), m.businessId(), taco + ":2");

		jdbc.update("UPDATE products SET price_cents = 9900, name = 'Taco gourmet' WHERE id = ?", taco);

		JsonNode order = fx.getOrder(c.token(), orderId);
		assertThat(order.at("/items/0/priceCents").asLong()).isEqualTo(1500);
		assertThat(order.at("/items/0/name").asString()).isEqualTo("Taco");
		assertThat(order.get("totalCents").asLong()).isEqualTo(3000);
	}

	@Test
	void ownerOrderingFromTheirOwnBusinessIsAWalkInWithoutCustomer() throws Exception {
		Merchant m = fx.merchant("walkin-m");
		String taco = fx.product(m, "Taco", 1500, true, 10);

		mvc.perform(auth(post("/orders"), m.token()).contentType(MediaType.APPLICATION_JSON)
			.content(OrderFixtures.orderBody(m.businessId(), taco + ":1")))
			.andExpect(status().isCreated())
			.andExpect(jsonPath("$.customerId").doesNotExist());
	}

	@Test
	void duplicateLinesAreSummedAgainstStock() throws Exception {
		Merchant m = fx.merchant("dup-m");
		Account c = fx.customer("dup-c");
		String taco = fx.product(m, "Taco", 100, true, 5);

		mvc.perform(auth(post("/orders"), c.token()).contentType(MediaType.APPLICATION_JSON)
			.content(OrderFixtures.orderBody(m.businessId(), taco + ":3", taco + ":3")))
			.andExpect(status().isConflict())
			.andExpect(jsonPath("$.error.code").value("INSUFFICIENT_STOCK"))
			.andExpect(jsonPath("$.error.message").value("Insufficient stock for product \"Taco\""));

		mvc.perform(auth(post("/orders"), c.token()).contentType(MediaType.APPLICATION_JSON)
			.content(OrderFixtures.orderBody(m.businessId(), taco + ":2", taco + ":3")))
			.andExpect(status().isCreated())
			.andExpect(jsonPath("$.items.length()").value(2))
			.andExpect(jsonPath("$.totalCents").value(500));
	}

	@Test
	void productsThatDoNotTrackStockIgnoreTheStockCheck() throws Exception {
		Merchant m = fx.merchant("untracked-m");
		Account c = fx.customer("untracked-c");
		String servicio = fx.product(m, "Servicio", 100, false, 0);

		mvc.perform(auth(post("/orders"), c.token()).contentType(MediaType.APPLICATION_JSON)
			.content(OrderFixtures.orderBody(m.businessId(), servicio + ":50")))
			.andExpect(status().isCreated());
	}

	@Test
	void invalidBodiesAre400ValidationErrors() throws Exception {
		Merchant m = fx.merchant("valid-m");
		Account c = fx.customer("valid-c");
		String taco = fx.product(m, "Taco", 100, true, 5);
		String item = "{\"productId\":\"" + taco + "\",\"qty\":1}";
		String[][] cases = {
				{ "[]", "body: must be a JSON object" },
				{ "{\"items\":[" + item + "]}", "businessId: is required" },
				{ "{\"businessId\":\"" + m.businessId() + "\"}", "items: must be a non-empty array" },
				{ "{\"businessId\":\"" + m.businessId() + "\",\"items\":[]}", "items: must be a non-empty array" },
				{ "{\"businessId\":\"" + m.businessId() + "\",\"items\":[{\"qty\":1}]}",
						"items.0.productId: is required" },
				{ "{\"businessId\":\"" + m.businessId() + "\",\"items\":[{\"productId\":\"" + taco + "\",\"qty\":0}]}",
						"items.0.qty: must be an integer between 1 and 10000" },
				{ "{\"businessId\":\"" + m.businessId() + "\",\"items\":[{\"productId\":\"" + taco + "\",\"qty\":1.5}]}",
						"items.0.qty: must be an integer between 1 and 10000" },
				{ "{\"businessId\":\"" + m.businessId() + "\",\"items\":[{\"productId\":\"" + taco
						+ "\",\"qty\":\"2\"}]}", "items.0.qty: must be an integer between 1 and 10000" },
				{ "{\"businessId\":\"" + m.businessId() + "\",\"items\":[{\"productId\":\"" + taco + "\",\"qty\":10001}]}",
						"items.0.qty: must be an integer between 1 and 10000" },
				{ "{\"businessId\":\"" + m.businessId() + "\",\"note\":5,\"items\":[" + item + "]}",
						"note: must be a string" },
				{ "{\"businessId\":\"" + m.businessId() + "\",\"note\":\"" + "x".repeat(501) + "\",\"items\":[" + item
						+ "]}", "note: at most 500 characters" } };
		for (String[] testCase : cases) {
			mvc.perform(auth(post("/orders"), c.token()).contentType(MediaType.APPLICATION_JSON).content(testCase[0]))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.error.code").value("VALIDATION_ERROR"))
				.andExpect(jsonPath("$.error.message").value(testCase[1]));
		}
		assertThat(fx.count("SELECT COUNT(*) FROM orders WHERE business_id = ?", m.businessId())).isZero();
	}

	@Test
	void unknownOrInactiveBusinessIs404() throws Exception {
		Merchant m = fx.merchant("nobiz-m");
		Account c = fx.customer("nobiz-c");
		String taco = fx.product(m, "Taco", 100, true, 5);

		mvc.perform(auth(post("/orders"), c.token()).contentType(MediaType.APPLICATION_JSON)
			.content(OrderFixtures.orderBody("nope", taco + ":1")))
			.andExpect(status().isNotFound())
			.andExpect(jsonPath("$.error.code").value("BUSINESS_NOT_FOUND"));

		jdbc.update("UPDATE businesses SET active = false WHERE id = ?", m.businessId());
		mvc.perform(auth(post("/orders"), c.token()).contentType(MediaType.APPLICATION_JSON)
			.content(OrderFixtures.orderBody(m.businessId(), taco + ":1")))
			.andExpect(status().isNotFound())
			.andExpect(jsonPath("$.error.code").value("BUSINESS_NOT_FOUND"));
	}

	@Test
	void productsOfAnotherBusinessOrInactiveOnesAre404() throws Exception {
		Merchant m = fx.merchant("noprod-m");
		Merchant other = fx.merchant("noprod-o");
		Account c = fx.customer("noprod-c");
		String mine = fx.product(m, "Mine", 100, true, 5);
		String theirs = fx.product(other, "Theirs", 100, true, 5);
		String retired = fx.product(m, "Retired", 100, true, 5);
		jdbc.update("UPDATE products SET active = false WHERE id = ?", retired);

		for (String line : new String[] { theirs + ":1", retired + ":1", "ghost:1" }) {
			mvc.perform(auth(post("/orders"), c.token()).contentType(MediaType.APPLICATION_JSON)
				.content(OrderFixtures.orderBody(m.businessId(), mine + ":1", line)))
				.andExpect(status().isNotFound())
				.andExpect(jsonPath("$.error.code").value("PRODUCT_NOT_FOUND"));
		}
		assertThat(fx.count("SELECT COUNT(*) FROM orders WHERE business_id = ?", m.businessId())).isZero();
	}

	@Test
	void everyOrderRouteRequiresAToken() throws Exception {
		mvc.perform(post("/orders").contentType(MediaType.APPLICATION_JSON).content("{}"))
			.andExpect(status().isUnauthorized());
		mvc.perform(get("/orders")).andExpect(status().isUnauthorized());
		mvc.perform(get("/orders/x")).andExpect(status().isUnauthorized());
		mvc.perform(post("/orders/x/pay")).andExpect(status().isUnauthorized());
	}

	// ---- GET /orders/:id and GET /orders

	@Test
	void onlyTheCustomerAndTheBusinessOwnerCanReadAnOrder() throws Exception {
		Merchant m = fx.merchant("read-m");
		Account c = fx.customer("read-c");
		Account stranger = fx.customer("read-s");
		Merchant otherOwner = fx.merchant("read-o");
		String taco = fx.product(m, "Taco", 100, true, 5);
		String orderId = fx.createOrder(c.token(), m.businessId(), taco + ":1");

		assertThat(fx.getOrder(c.token(), orderId).get("id").asString()).isEqualTo(orderId);
		assertThat(fx.getOrder(m.token(), orderId).get("id").asString()).isEqualTo(orderId);
		for (String token : new String[] { stranger.token(), otherOwner.token() }) {
			mvc.perform(auth(get("/orders/" + orderId), token))
				.andExpect(status().isNotFound())
				.andExpect(jsonPath("$.error.code").value("ORDER_NOT_FOUND"));
		}
		mvc.perform(auth(get("/orders/missing"), c.token()))
			.andExpect(status().isNotFound())
			.andExpect(jsonPath("$.error.code").value("ORDER_NOT_FOUND"));
	}

	@Test
	void listFiltersByRoleAndStatusNewestFirst() throws Exception {
		Merchant m = fx.merchant("list-m");
		Account c = fx.customer("list-c");
		Account other = fx.customer("list-x");
		String taco = fx.product(m, "Taco", 100, true, 50);
		String o1 = fx.createOrder(c.token(), m.businessId(), taco + ":1");
		String o2 = fx.createOrder(c.token(), m.businessId(), taco + ":1");
		String walkIn = fx.createOrder(m.token(), m.businessId(), taco + ":1");
		String othersOrder = fx.createOrder(other.token(), m.businessId(), taco + ":1");
		long now = Instant.now().getEpochSecond();
		jdbc.update("UPDATE orders SET created_at = ? WHERE id = ?", now - 40, o1);
		jdbc.update("UPDATE orders SET created_at = ? WHERE id = ?", now - 30, o2);
		jdbc.update("UPDATE orders SET created_at = ? WHERE id = ?", now - 20, walkIn);
		jdbc.update("UPDATE orders SET created_at = ? WHERE id = ?", now - 10, othersOrder);
		jdbc.update("UPDATE orders SET status = 'paid', paid_at = ? WHERE id = ?", now, o2);

		assertThat(ids(c.token(), "/orders")).containsExactly(o2, o1);
		assertThat(ids(c.token(), "/orders?role=customer")).containsExactly(o2, o1);
		assertThat(ids(c.token(), "/orders?role=business")).isEmpty();
		assertThat(ids(m.token(), "/orders")).containsExactly(othersOrder, walkIn, o2, o1);
		assertThat(ids(m.token(), "/orders?role=business")).containsExactly(othersOrder, walkIn, o2, o1);
		assertThat(ids(m.token(), "/orders?role=customer")).isEmpty();
		assertThat(ids(m.token(), "/orders?status=paid")).containsExactly(o2);
		assertThat(ids(m.token(), "/orders?role=business&status=pending_payment")).containsExactly(othersOrder, walkIn,
				o1);
		assertThat(ids(m.token(), "/orders?status=")).hasSize(4);
		assertThat(ids(m.token(), "/orders?status=delivered")).isEmpty();
		assertThat(ids(other.token(), "/orders")).containsExactly(othersOrder);
	}

	@Test
	void listWithABadRoleOrStatusIs400() throws Exception {
		Account c = fx.customer("badq-c");

		for (String query : new String[] { "role=admin", "role=", "status=bogus" }) {
			mvc.perform(auth(get("/orders?" + query), c.token()))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.error.code").value("VALIDATION_ERROR"));
		}
	}

	@Test
	void listCarriesItemsAndTheLatestPayment() throws Exception {
		Merchant m = fx.merchant("hyd-m");
		Account c = fx.customer("hyd-c");
		String taco = fx.product(m, "Taco", 100, true, 5);
		String orderId = fx.createOrder(c.token(), m.businessId(), taco + ":2");
		JsonNode qr = fx.pay(c.token(), orderId);

		mvc.perform(auth(get("/orders"), c.token()))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$[0].items.length()").value(1))
			.andExpect(jsonPath("$[0].payment.status").value("pending"))
			.andExpect(jsonPath("$[0].payment.codiQrId").value(qr.get("codiQrId").asString()))
			.andExpect(jsonPath("$[0].payment.amountCents").value(200));
	}

	@Test
	void stalePendingOrdersExpireWhenReadAndTheirQrStopsBeingPayable() throws Exception {
		Merchant m = fx.merchant("exp-m");
		Account c = fx.customer("exp-c");
		String taco = fx.product(m, "Taco", 100, true, 5);
		String stale = fx.createOrder(c.token(), m.businessId(), taco + ":1");
		String fresh = fx.createOrder(c.token(), m.businessId(), taco + ":1");
		fx.pay(c.token(), stale);
		long now = Instant.now().getEpochSecond();
		jdbc.update("UPDATE orders SET created_at = ? WHERE id = ?", now - 1000, stale);
		jdbc.update("UPDATE orders SET created_at = ? WHERE id = ?", now - 890, fresh);

		JsonNode read = fx.getOrder(c.token(), stale);
		assertThat(read.get("status").asString()).isEqualTo("expired");
		assertThat(read.at("/payment/status").asString()).isEqualTo("expired");
		assertThat(fx.getOrder(c.token(), fresh).get("status").asString()).isEqualTo("pending_payment");
		mvc.perform(auth(post("/orders/" + stale + "/pay"), c.token()))
			.andExpect(status().isConflict())
			.andExpect(jsonPath("$.error.code").value("INVALID_TRANSITION"));
	}

	@Test
	void listingAlsoExpiresStaleOrders() throws Exception {
		Merchant m = fx.merchant("lexp-m");
		Account c = fx.customer("lexp-c");
		String taco = fx.product(m, "Taco", 100, true, 5);
		String stale = fx.createOrder(c.token(), m.businessId(), taco + ":1");
		jdbc.update("UPDATE orders SET created_at = ? WHERE id = ?", Instant.now().getEpochSecond() - 1000, stale);

		assertThat(ids(c.token(), "/orders?status=expired")).containsExactly(stale);
		assertThat(ids(m.token(), "/orders?role=business&status=pending_payment")).isEmpty();
	}

	// ---- POST /orders/:id/pay

	@Test
	void payAsksPeyForACodiQrOfTheOrderTotalInCentavos() throws Exception {
		Merchant m = fx.merchant("pay-m");
		Account c = fx.customer("pay-c");
		String taco = fx.product(m, "Taco", 1500, true, 10);
		String orderId = fx.createOrder(c.token(), m.businessId(), taco + ":3");
		long before = Instant.now().getEpochSecond();

		mvc.perform(auth(post("/orders/" + orderId + "/pay"), c.token()))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.qrString").value(org.hamcrest.Matchers.startsWith("00020101fake")))
			.andExpect(jsonPath("$.codiQrId").value(org.hamcrest.Matchers.startsWith("qr_fake_")))
			.andExpect(jsonPath("$.amountCents").value(4500))
			.andExpect(jsonPath("$.expiresAt").value(org.hamcrest.Matchers.greaterThanOrEqualTo((int) before + 600)));

		assertThat(pey.qrCalls).hasSize(1);
		var req = pey.qrCalls.getFirst();
		assertThat(req.amountCents()).isEqualTo(4500);
		assertThat(req.concept()).isEqualTo("Pedido " + orderId.substring(orderId.length() - 6));
		assertThat(req.numRef()).matches("[0-9]{7}").isEqualTo(OrderService.deriveNumRef(orderId));
		assertThat(req.expirationSec()).isEqualTo(600);
		assertThat(req.bankAccountId()).isNull();
		assertThat(req.metadata()).containsEntry("orderId", orderId).containsEntry("businessId", m.businessId());
		assertThat(fx.count("SELECT COUNT(*) FROM payments WHERE order_id = ? AND status = 'pending' "
				+ "AND amount_cents = 4500", orderId)).isEqualTo(1);
		assertThat(fx.orderStatus(orderId)).isEqualTo("pending_payment");
	}

	@Test
	void theQrIsRoutedToTheMerchantAccountOnlyOnceCodiIsActive() throws Exception {
		Merchant m = fx.merchant("route-m");
		Account c = fx.customer("route-c");
		String taco = fx.product(m, "Taco", 100, true, 10);
		String o1 = fx.createOrder(c.token(), m.businessId(), taco + ":1");
		String o2 = fx.createOrder(c.token(), m.businessId(), taco + ":1");
		jdbc.update("UPDATE businesses SET pey_bank_account_id = 'ba_9', codi_status = 'PENDING' WHERE id = ?",
				m.businessId());

		fx.pay(c.token(), o1);
		jdbc.update("UPDATE businesses SET codi_status = 'ACTIVE' WHERE id = ?", m.businessId());
		fx.pay(c.token(), o2);

		assertThat(pey.qrCalls.get(0).bankAccountId()).isNull();
		assertThat(pey.qrCalls.get(1).bankAccountId()).isEqualTo("ba_9");
	}

	@Test
	void payingTwiceReusesTheLiveQrAndAnExpiredQrIsReplaced() throws Exception {
		Merchant m = fx.merchant("reuse-m");
		Account c = fx.customer("reuse-c");
		String taco = fx.product(m, "Taco", 100, true, 10);
		String orderId = fx.createOrder(c.token(), m.businessId(), taco + ":1");

		JsonNode first = fx.pay(c.token(), orderId);
		JsonNode again = fx.pay(m.token(), orderId);
		assertThat(again).isEqualTo(first);
		assertThat(pey.qrCalls).hasSize(1);

		jdbc.update("UPDATE payments SET expires_at = ? WHERE order_id = ?", Instant.now().getEpochSecond() - 1,
				orderId);
		JsonNode renewed = fx.pay(c.token(), orderId);
		assertThat(renewed.get("codiQrId").asString()).isNotEqualTo(first.get("codiQrId").asString());
		assertThat(pey.qrCalls).hasSize(2);
		assertThat(fx.count("SELECT COUNT(*) FROM payments WHERE order_id = ?", orderId)).isEqualTo(2);
	}

	@Test
	void onlyParticipantsCanPayAndOnlyPendingOrdersCanBePaid() throws Exception {
		Merchant m = fx.merchant("authz-m");
		Account c = fx.customer("authz-c");
		Account stranger = fx.customer("authz-s");
		String taco = fx.product(m, "Taco", 100, true, 10);
		String orderId = fx.createOrder(c.token(), m.businessId(), taco + ":1");

		mvc.perform(auth(post("/orders/" + orderId + "/pay"), stranger.token()))
			.andExpect(status().isNotFound())
			.andExpect(jsonPath("$.error.code").value("ORDER_NOT_FOUND"));
		mvc.perform(auth(post("/orders/ghost/pay"), c.token())).andExpect(status().isNotFound());
		assertThat(pey.qrCalls).isEmpty();

		for (String status : new String[] { "paid", "preparing", "cancelled", "delivered" }) {
			jdbc.update("UPDATE orders SET status = ? WHERE id = ?", status, orderId);
			mvc.perform(auth(post("/orders/" + orderId + "/pay"), c.token()))
				.andExpect(status().isConflict())
				.andExpect(jsonPath("$.error.code").value("INVALID_TRANSITION"));
		}
		assertThat(pey.qrCalls).isEmpty();
	}

	@Test
	void aPeyFailureSurfacesAsItsOwnErrorAndStoresNoPayment() throws Exception {
		Merchant m = fx.merchant("fail-m");
		Account c = fx.customer("fail-c");
		String taco = fx.product(m, "Taco", 100, true, 10);
		String orderId = fx.createOrder(c.token(), m.businessId(), taco + ":1");

		pey.failure = new AppException(HttpStatus.BAD_GATEWAY, "PEY_ERROR", "pey down [req_1]");
		mvc.perform(auth(post("/orders/" + orderId + "/pay"), c.token()))
			.andExpect(status().isBadGateway())
			.andExpect(jsonPath("$.error.code").value("PEY_ERROR"))
			.andExpect(jsonPath("$.error.message").value("pey down [req_1]"));
		pey.failure = new AppException(HttpStatus.SERVICE_UNAVAILABLE, "PEY_NOT_CONFIGURED", "no key");
		mvc.perform(auth(post("/orders/" + orderId + "/pay"), c.token()))
			.andExpect(status().isServiceUnavailable())
			.andExpect(jsonPath("$.error.code").value("PEY_NOT_CONFIGURED"));

		assertThat(fx.count("SELECT COUNT(*) FROM payments WHERE order_id = ?", orderId)).isZero();
		pey.failure = null;
		fx.pay(c.token(), orderId);
		assertThat(fx.count("SELECT COUNT(*) FROM payments WHERE order_id = ?", orderId)).isEqualTo(1);
	}

	@Test
	void numRefMatchesTheNodeDerivation() {
		// reference values computed with apps/api/src/services/order.service.ts deriveNumRef
		assertThat(OrderService.deriveNumRef("01JABCDEFGHJKMNPQRSTVWXYZ0")).isEqualTo("3628795");
		assertThat(OrderService.deriveNumRef("O12345")).isEqualTo("5495684");
		assertThat(OrderService.deriveNumRef("x")).isEqualTo("1000120");
	}

	// ---- helpers

	private java.util.List<String> ids(String token, String url) throws Exception {
		var res = mvc.perform(auth(get(url), token)).andExpect(status().isOk()).andReturn();
		var out = new java.util.ArrayList<String>();
		for (JsonNode o : fx.json.readTree(res.getResponse().getContentAsString())) {
			out.add(o.get("id").asString());
		}
		return out;
	}

	private static MockHttpServletRequestBuilder auth(MockHttpServletRequestBuilder req, String token) {
		return req.header("Authorization", "Bearer " + token);
	}

}
