package mx.paydmex.api.order;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Base64;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

import com.github.f4b6a3.ulid.UlidCreator;

import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

/** Shared test data builders for the order/webhook tests. Everything it creates is removed by {@link #cleanup()}. */
final class OrderFixtures {

	/** Base64 of the dummy secret in application-test.yml (without the whsec_ prefix). */
	static final String WEBHOOK_SECRET_B64 = "dGVzdC13ZWJob29rLXNlY3JldC0wMTIzNDU2Nzg5";

	static final String WEBHOOK_ID_PREFIX = "whtest-";

	private static final String DOMAIN = "@orders-test.mx";

	record Account(String id, String token) {
	}

	record Merchant(String id, String token, String businessId) {
	}

	final MockMvc mvc;

	final JdbcTemplate jdbc;

	final JsonMapper json = JsonMapper.builder().build();

	OrderFixtures(MockMvc mvc, JdbcTemplate jdbc) {
		this.mvc = mvc;
		this.jdbc = jdbc;
	}

	// ---- accounts and catalog

	Account customer(String label) throws Exception {
		JsonNode r = register(label);
		return new Account(r.at("/user/id").asString(), r.get("token").asString());
	}

	Merchant merchant(String label) throws Exception {
		JsonNode r = register(label);
		String token = r.get("token").asString();
		var biz = mvc.perform(post("/me/business").header("Authorization", "Bearer " + token)
			.contentType(MediaType.APPLICATION_JSON)
			.content("{\"name\":\"Negocio " + label + "\",\"category\":\"food\",\"prepType\":\"instant\"}"))
			.andExpect(status().isCreated())
			.andReturn();
		return new Merchant(r.at("/user/id").asString(), token,
				json.readTree(biz.getResponse().getContentAsString()).get("id").asString());
	}

	/** Monotonic ULID ids: products created in sequence sort in creation order (the webhook locks in id order). */
	String product(Merchant m, String name, long priceCents, boolean trackStock, int stock) {
		String id = UlidCreator.getMonotonicUlid().toString();
		jdbc.update("INSERT INTO products (id, business_id, name, price_cents, track_stock, stock, active, created_at) "
				+ "VALUES (?,?,?,?,?,?,true,1)", id, m.businessId(), name, priceCents, trackStock, stock);
		return id;
	}

	// ---- orders

	/** Body of POST /orders; each line is {@code "<productId>:<qty>"}. */
	static String orderBody(String businessId, String... lines) {
		var items = new StringBuilder();
		for (String line : lines) {
			String[] parts = line.split(":");
			items.append(items.isEmpty() ? "" : ",")
				.append("{\"productId\":\"")
				.append(parts[0])
				.append("\",\"qty\":")
				.append(parts[1])
				.append('}');
		}
		return "{\"businessId\":\"" + businessId + "\",\"items\":[" + items + "]}";
	}

	/** Creates an order through the API as {@code token}; returns its id. */
	String createOrder(String token, String businessId, String... lines) throws Exception {
		var res = mvc.perform(post("/orders").header("Authorization", "Bearer " + token)
			.contentType(MediaType.APPLICATION_JSON)
			.content(orderBody(businessId, lines)))
			.andExpect(status().isCreated())
			.andReturn();
		return json.readTree(res.getResponse().getContentAsString()).get("id").asString();
	}

	/** Charges the order through the API; returns the pay response. */
	JsonNode pay(String token, String orderId) throws Exception {
		var res = mvc.perform(post("/orders/" + orderId + "/pay").header("Authorization", "Bearer " + token))
			.andExpect(status().isOk())
			.andReturn();
		return json.readTree(res.getResponse().getContentAsString());
	}

	JsonNode getOrder(String token, String orderId) throws Exception {
		var res = mvc.perform(get("/orders/" + orderId).header("Authorization", "Bearer " + token))
			.andExpect(status().isOk())
			.andReturn();
		return json.readTree(res.getResponse().getContentAsString());
	}

	// ---- webhook

	static String sign(String webhookId, long timestamp, String body) throws Exception {
		return sign(webhookId, timestamp, body, WEBHOOK_SECRET_B64);
	}

	static String sign(String webhookId, long timestamp, String body, String secretB64) throws Exception {
		Mac mac = Mac.getInstance("HmacSHA256");
		mac.init(new SecretKeySpec(Base64.getDecoder().decode(secretB64), "HmacSHA256"));
		byte[] sig = mac.doFinal((webhookId + "." + timestamp + "." + body).getBytes(StandardCharsets.UTF_8));
		return Base64.getEncoder().encodeToString(sig);
	}

	/** A correctly signed pey webhook delivery with the current timestamp. */
	static MockHttpServletRequestBuilder webhook(String webhookId, String body) throws Exception {
		long now = Instant.now().getEpochSecond();
		return webhookWith(webhookId, now, "v1," + sign(webhookId, now, body), body);
	}

	static MockHttpServletRequestBuilder webhookWith(String webhookId, long timestamp, String signatureHeader,
			String body) {
		return post("/webhooks/pey").contentType(MediaType.APPLICATION_JSON)
			.header("webhook-id", webhookId)
			.header("webhook-timestamp", timestamp)
			.header("webhook-signature", signatureHeader)
			.content(body);
	}

	static String paymentReceived(String codiQrId, String transactionId) {
		return "{\"type\":\"codi.qr.payment_received\",\"amount\":0.01,\"codiQrId\":\"" + codiQrId
				+ "\",\"transactionId\":\"" + transactionId + "\",\"numRef\":\"1234567\",\"concept\":\"Pedido\","
				+ "\"metadata\":{}}";
	}

	// ---- db

	int count(String sql, Object... args) {
		return jdbc.queryForObject(sql, Integer.class, args);
	}

	int stockOf(String productId) {
		return count("SELECT stock FROM products WHERE id = ?", productId);
	}

	String orderStatus(String orderId) {
		return jdbc.queryForObject("SELECT status FROM orders WHERE id = ?", String.class, orderId);
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
		jdbc.update("DELETE FROM webhook_events WHERE id LIKE '" + WEBHOOK_ID_PREFIX + "%'");
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
