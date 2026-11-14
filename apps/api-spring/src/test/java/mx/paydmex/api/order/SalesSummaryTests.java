package mx.paydmex.api.order;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import mx.paydmex.api.pey.FakePeyClient;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(FakePeyClient.Config.class)
class SalesSummaryTests {

	@Autowired
	MockMvc mvc;

	@Autowired
	JdbcTemplate jdbc;

	private final JsonMapper json = JsonMapper.builder().build();

	private int seq;

	record Owner(String id, String token, String businessId) {
	}

	@AfterEach
	void cleanup() {
		String owners = "(SELECT id FROM users WHERE email LIKE '%@sales-test.mx')";
		String businesses = "(SELECT id FROM businesses WHERE owner_id IN " + owners + ")";
		String orders = "(SELECT id FROM orders WHERE business_id IN " + businesses + ")";
		jdbc.update("DELETE FROM order_items WHERE order_id IN " + orders);
		jdbc.update("DELETE FROM orders WHERE business_id IN " + businesses);
		jdbc.update("DELETE FROM products WHERE business_id IN " + businesses);
		jdbc.update("DELETE FROM businesses WHERE owner_id IN " + owners);
		jdbc.update("DELETE FROM users WHERE email LIKE '%@sales-test.mx'");
	}

	@Test
	void emptyBusinessReturnsZeros() throws Exception {
		Owner o = ownerWithBusiness("empty");
		mvc.perform(authGet(o, "/business/sales/summary"))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.totalCents").value(0))
			.andExpect(jsonPath("$.orders").value(0))
			.andExpect(jsonPath("$.topProducts.length()").value(0));
	}

	@Test
	void onlyPaidStatusesOfTheOwnBusinessCount() throws Exception {
		Owner a = ownerWithBusiness("paida");
		Owner b = ownerWithBusiness("paidb");
		String pa = product(a, "Taco");
		String pb = product(b, "Ajeno");
		order(a, "paid", 100, pa, "Taco", 500, 2);
		order(a, "preparing", 100, pa, "Taco", 500, 4);
		order(a, "ready", 100, pa, "Taco", 300, 1);
		order(a, "delivered", 100, pa, "Taco", 350, 2);
		order(a, "pending_payment", 100, pa, "Taco", 9999, 1);
		order(a, "cancelled", 100, pa, "Taco", 9999, 1);
		order(a, "expired", 100, pa, "Taco", 9999, 1);
		order(b, "paid", 100, pb, "Ajeno", 5000, 1);

		mvc.perform(authGet(a, "/business/sales/summary"))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.totalCents").value(4000))
			.andExpect(jsonPath("$.orders").value(4))
			.andExpect(jsonPath("$.topProducts.length()").value(1))
			.andExpect(jsonPath("$.topProducts[0].productId").value(pa))
			.andExpect(jsonPath("$.topProducts[0].name").value("Taco"))
			.andExpect(jsonPath("$.topProducts[0].qty").value(9))
			.andExpect(jsonPath("$.topProducts[0].revenueCents").value(4000));
	}

	@Test
	void fromAndToAreInclusiveBoundsOnCreatedAt() throws Exception {
		Owner o = ownerWithBusiness("range");
		String p = product(o, "Taco");
		order(o, "paid", 1000, p, "Taco", 100, 1);
		order(o, "paid", 2000, p, "Taco", 200, 1);
		order(o, "paid", 3000, p, "Taco", 400, 1);

		summary(o, "", 700, 3);
		summary(o, "?from=2000", 600, 2);
		summary(o, "?to=2000", 300, 2);
		summary(o, "?from=2000&to=2000", 200, 1);
		summary(o, "?from=3001", 0, 0);
		summary(o, "?from=3000&to=1000", 0, 0);
		summary(o, "?from=&to=", 700, 3);
	}

	@Test
	void invalidBoundsAre400() throws Exception {
		Owner o = ownerWithBusiness("badrange");
		for (String q : new String[] { "from=abc", "to=1.5", "from=1e3" }) {
			String field = q.substring(0, q.indexOf('='));
			mvc.perform(authGet(o, "/business/sales/summary?" + q))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.error.code").value("VALIDATION_ERROR"))
				.andExpect(jsonPath("$.error.message").value(field + ": must be an integer"));
		}
	}

	@Test
	void topProductsSortByQtyThenRevenueCappedAtTenAndRenamedProductsMerge() throws Exception {
		Owner o = ownerWithBusiness("top");
		String big = product(o, "Big");
		String rich = product(o, "Rich");
		String poor = product(o, "Poor");
		String renamed = product(o, "Renamed");
		// Order 1 (older): the renamed product still has its old name
		String o1 = order(o, "paid", 100, renamed, "Old name", 100, 1);
		item(o1, big, "Big", 100, 5);
		item(o1, rich, "Rich", 900, 2);
		item(o1, poor, "Poor", 100, 2);
		// Order 2 (newer)
		String o2 = order(o, "delivered", 200, renamed, "New name", 100, 2);
		item(o2, big, "Big", 100, 1);

		JsonNode top = json.readTree(mvc.perform(authGet(o, "/business/sales/summary"))
			.andExpect(status().isOk())
			.andReturn()
			.getResponse()
			.getContentAsString())
			.get("topProducts");
		// qty: big 6, renamed 3, rich 2 (revenue 1800), poor 2 (revenue 200)
		assertThat(top).hasSize(4);
		assertThat(top.get(0).get("productId").asString()).isEqualTo(big);
		assertThat(top.get(0).get("qty").asLong()).isEqualTo(6);
		assertThat(top.get(1).get("productId").asString()).isEqualTo(renamed);
		assertThat(top.get(1).get("name").asString()).isEqualTo("New name");
		assertThat(top.get(1).get("qty").asLong()).isEqualTo(3);
		assertThat(top.get(1).get("revenueCents").asLong()).isEqualTo(300);
		assertThat(top.get(2).get("productId").asString()).isEqualTo(rich);
		assertThat(top.get(2).get("revenueCents").asLong()).isEqualTo(1800);
		assertThat(top.get(3).get("productId").asString()).isEqualTo(poor);

		// cap at 10
		for (int i = 0; i < 12; i++) {
			String extra = product(o, "Extra" + i);
			item(o1, extra, "Extra" + i, 10, 1);
		}
		mvc.perform(authGet(o, "/business/sales/summary"))
			.andExpect(jsonPath("$.topProducts.length()").value(10));
	}

	// ---- helpers

	private void summary(Owner o, String query, long totalCents, int orders) throws Exception {
		mvc.perform(authGet(o, "/business/sales/summary" + query))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.totalCents").value(totalCents))
			.andExpect(jsonPath("$.orders").value(orders));
	}

	private Owner ownerWithBusiness(String label) throws Exception {
		String email = label + "@sales-test.mx";
		var reg = mvc.perform(post("/auth/register").contentType(MediaType.APPLICATION_JSON)
			.content("{\"email\":\"" + email + "\",\"password\":\"password-1\",\"name\":\"" + label + "\"}"))
			.andExpect(status().isCreated())
			.andReturn();
		JsonNode r = json.readTree(reg.getResponse().getContentAsString());
		String token = r.get("token").asString();
		var biz = mvc.perform(post("/me/business").header("Authorization", "Bearer " + token)
			.contentType(MediaType.APPLICATION_JSON)
			.content("{\"name\":\"Negocio " + label + "\",\"category\":\"food\",\"prepType\":\"instant\"}"))
			.andExpect(status().isCreated())
			.andReturn();
		return new Owner(r.at("/user/id").asString(), token,
				json.readTree(biz.getResponse().getContentAsString()).get("id").asString());
	}

	private String product(Owner o, String name) {
		String id = "P" + o.businessId().substring(0, 8) + (++seq) + name;
		jdbc.update("INSERT INTO products (id, business_id, name, price_cents, track_stock, stock, active, created_at) "
				+ "VALUES (?,?,?,100,true,10,true,1)", id, o.businessId(), name);
		return id;
	}

	/** Inserts an order with one item; the order total is price x qty. Returns the order id. */
	private String order(Owner o, String status, long createdAt, String productId, String name, long priceCents,
			int qty) {
		String id = "O" + o.businessId().substring(0, 8) + (++seq);
		jdbc.update("INSERT INTO orders (id, business_id, status, total_cents, created_at) VALUES (?,?,?,?,?)", id,
				o.businessId(), status, priceCents * qty, createdAt);
		item(id, productId, name, priceCents, qty);
		return id;
	}

	private void item(String orderId, String productId, String name, long priceCents, int qty) {
		jdbc.update("INSERT INTO order_items (id, order_id, product_id, name, price_cents, qty) VALUES (?,?,?,?,?,?)",
				"I" + (++seq), orderId, productId, name, priceCents, qty);
	}

	private static MockHttpServletRequestBuilder authGet(Owner o, String url) {
		return get(url).header("Authorization", "Bearer " + o.token());
	}

}
