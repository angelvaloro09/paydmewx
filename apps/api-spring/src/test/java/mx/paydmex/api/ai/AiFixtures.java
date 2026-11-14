package mx.paydmex.api.ai;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

/** Test data for the assistant tests. Everything it creates is removed by {@link #cleanup()}. */
final class AiFixtures {

	private static final String DOMAIN = "@ai-test.mx";

	record Account(String id, String token) {
	}

	record Merchant(String id, String token, String businessId) {
	}

	final MockMvc mvc;

	final JdbcTemplate jdbc;

	final JsonMapper json = JsonMapper.builder().build();

	AiFixtures(MockMvc mvc, JdbcTemplate jdbc) {
		this.mvc = mvc;
		this.jdbc = jdbc;
	}

	Account customer(String label) throws Exception {
		JsonNode r = register(label);
		return new Account(r.at("/user/id").asString(), r.get("token").asString());
	}

	Merchant merchant(String label) throws Exception {
		JsonNode r = register(label);
		String token = r.get("token").asString();
		var biz = mvc.perform(post("/me/business").header("Authorization", "Bearer " + token)
			.contentType(MediaType.APPLICATION_JSON)
			.content("{\"name\":\"Tacos " + label + "\",\"category\":\"food\",\"prepType\":\"instant\"}"))
			.andExpect(status().isCreated())
			.andReturn();
		return new Merchant(r.at("/user/id").asString(), token,
				json.readTree(biz.getResponse().getContentAsString()).get("id").asString());
	}

	/** Creates a product through the owner API; returns its id. */
	String product(Merchant m, String name, long priceCents, boolean trackStock, int stock) throws Exception {
		var res = mvc.perform(post("/business/products").header("Authorization", "Bearer " + m.token())
			.contentType(MediaType.APPLICATION_JSON)
			.content("{\"name\":\"" + name + "\",\"priceCents\":" + priceCents + ",\"trackStock\":" + trackStock
					+ ",\"stock\":" + stock + "}"))
			.andExpect(status().isCreated())
			.andReturn();
		return json.readTree(res.getResponse().getContentAsString()).get("id").asString();
	}

	ResultActions assist(String token, String body) throws Exception {
		var req = post("/ai/assist").contentType(MediaType.APPLICATION_JSON).content(body);
		return mvc.perform(token == null ? req : req.header("Authorization", "Bearer " + token));
	}

	static String message(String text) {
		return "{\"message\":\"" + text + "\"}";
	}

	JsonNode assistOk(String token, String text) throws Exception {
		var res = assist(token, message(text)).andExpect(status().isOk()).andReturn();
		return json.readTree(res.getResponse().getContentAsString());
	}

	int count(String sql, Object... args) {
		return jdbc.queryForObject(sql, Integer.class, args);
	}

	void cleanup() {
		String users = "(SELECT id FROM users WHERE email LIKE '%" + DOMAIN + "')";
		String businesses = "(SELECT id FROM businesses WHERE owner_id IN " + users + ")";
		String orders = "(SELECT id FROM orders WHERE business_id IN " + businesses + ")";
		String products = "(SELECT id FROM products WHERE business_id IN " + businesses + ")";
		jdbc.update("DELETE FROM payments WHERE order_id IN " + orders);
		jdbc.update("DELETE FROM order_items WHERE order_id IN " + orders);
		jdbc.update("DELETE FROM orders WHERE business_id IN " + businesses);
		jdbc.update("DELETE FROM stock_movements WHERE product_id IN " + products);
		jdbc.update("DELETE FROM products WHERE business_id IN " + businesses);
		jdbc.update("DELETE FROM businesses WHERE owner_id IN " + users);
		jdbc.update("DELETE FROM users WHERE email LIKE '%" + DOMAIN + "'");
	}

	private JsonNode register(String label) throws Exception {
		var reg = mvc.perform(post("/auth/register").contentType(MediaType.APPLICATION_JSON)
			.content("{\"email\":\"" + label + DOMAIN + "\",\"password\":\"password-1\",\"name\":\"" + label + "\"}"))
			.andExpect(status().isCreated())
			.andReturn();
		return json.readTree(reg.getResponse().getContentAsString());
	}

}
