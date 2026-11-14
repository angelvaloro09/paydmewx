package mx.paydmex.api.product;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.MACSigner;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;

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
class ProductTests {

	private static final String SECRET = "unit-test-only-hs256-key-0123456789-abcdef";

	private static final String ULID = "[0-9A-HJKMNP-TV-Z]{26}";

	@Autowired
	MockMvc mvc;

	@Autowired
	JdbcTemplate jdbc;

	private final JsonMapper json = JsonMapper.builder().build();

	record Owner(String id, String token, String businessId) {
	}

	@AfterEach
	void cleanup() {
		String owners = "(SELECT id FROM users WHERE email LIKE '%@prod-test.mx')";
		String businesses = "(SELECT id FROM businesses WHERE owner_id IN " + owners + ")";
		String products = "(SELECT id FROM products WHERE business_id IN " + businesses + ")";
		jdbc.update("DELETE FROM stock_movements WHERE product_id IN " + products);
		jdbc.update("DELETE FROM products WHERE business_id IN " + businesses);
		jdbc.update("DELETE FROM businesses WHERE owner_id IN " + owners);
		jdbc.update("DELETE FROM users WHERE email LIKE '%@prod-test.mx'");
	}

	// ---- POST /business/products

	@Test
	void createReturnsContractShapeWithDefaults() throws Exception {
		Owner o = ownerWithBusiness("shape");
		long before = Instant.now().getEpochSecond();
		var res = mvc.perform(authPost(o, "/business/products", "{\"name\":\"  Taco \",\"priceCents\":2500}"))
			.andExpect(status().isCreated())
			.andExpect(jsonPath("$.id").value(org.hamcrest.Matchers.matchesPattern(ULID)))
			.andExpect(jsonPath("$.businessId").value(o.businessId()))
			.andExpect(jsonPath("$.name").value("Taco"))
			.andExpect(jsonPath("$.priceCents").value(2500))
			.andExpect(jsonPath("$.trackStock").value(true))
			.andExpect(jsonPath("$.stock").value(0))
			.andExpect(jsonPath("$.prepMinutes").value(org.hamcrest.Matchers.nullValue()))
			.andExpect(jsonPath("$.imageUrl").value(org.hamcrest.Matchers.nullValue()))
			.andExpect(jsonPath("$.active").value(true))
			.andReturn();
		JsonNode body = json.readTree(res.getResponse().getContentAsString());
		assertThat(body.get("createdAt").asLong()).isBetween(before, Instant.now().getEpochSecond() + 1);
		assertThat(movementCount(body.get("id").asString())).isZero();
	}

	@Test
	void createWithStockLogsAnInitialMovement() throws Exception {
		Owner o = ownerWithBusiness("initial");
		String id = createProduct(o, "{\"name\":\"Agua\",\"priceCents\":1500,\"stock\":12,\"prepMinutes\":3,"
				+ "\"imageUrl\":\"https://x.mx/a.png\",\"trackStock\":false}");
		assertThat(jdbc.queryForObject("SELECT stock FROM products WHERE id=?", Integer.class, id)).isEqualTo(12);
		assertThat(jdbc.queryForObject("SELECT track_stock FROM products WHERE id=?", Boolean.class, id)).isFalse();
		assertThat(jdbc.queryForObject("SELECT prep_minutes FROM products WHERE id=?", Integer.class, id))
			.isEqualTo(3);
		var m = jdbc.queryForMap("SELECT delta, reason FROM stock_movements WHERE product_id=?", id);
		assertThat(m.get("delta")).isEqualTo(12);
		assertThat(m.get("reason")).isEqualTo("initial_stock");
	}

	@Test
	void createValidationErrors() throws Exception {
		Owner o = ownerWithBusiness("val");
		expectCreateError(o, "{\"priceCents\":100}", "name: is required");
		expectCreateError(o, "{\"name\":\"   \",\"priceCents\":100}", "name: is required");
		expectCreateError(o, "{\"name\":5,\"priceCents\":100}", "name: must be a string");
		expectCreateError(o, "{\"name\":\"A\"}", "priceCents: is required");
		expectCreateError(o, "{\"name\":\"A\",\"priceCents\":-1}", "priceCents: must be a non-negative integer");
		expectCreateError(o, "{\"name\":\"A\",\"priceCents\":10.5}", "priceCents: must be a non-negative integer");
		expectCreateError(o, "{\"name\":\"A\",\"priceCents\":\"100\"}", "priceCents: must be a non-negative integer");
		expectCreateError(o, "{\"name\":\"A\",\"priceCents\":100,\"stock\":-1}",
				"stock: must be a non-negative integer");
		expectCreateError(o, "{\"name\":\"A\",\"priceCents\":100,\"stock\":3000000000}",
				"stock: must be a non-negative integer");
		expectCreateError(o, "{\"name\":\"A\",\"priceCents\":100,\"prepMinutes\":0}",
				"prepMinutes: must be a positive integer");
		expectCreateError(o, "{\"name\":\"A\",\"priceCents\":100,\"trackStock\":\"yes\"}",
				"trackStock: must be a boolean");
		expectCreateError(o, "{\"name\":\"A\",\"priceCents\":100,\"imageUrl\":7}", "imageUrl: must be a string");
		expectCreateError(o, "[1]", "body: must be a JSON object");
		assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM products WHERE business_id=?", Integer.class,
				o.businessId()))
			.isZero();
	}

	// ---- auth / ownership gate (every owner route)

	@Test
	void ownerRoutesRequireAuthAnExistingUserAndABusiness() throws Exception {
		Owner noBusiness = signup("nobiz");
		String ghost = token("01ARZ3NDEKTSV4RRFFQ69G5FAV");
		// builders accumulate headers, so each round gets fresh ones
		for (MockHttpServletRequestBuilder call : ownerCalls()) {
			mvc.perform(call).andExpect(status().isUnauthorized());
		}
		for (MockHttpServletRequestBuilder call : ownerCalls()) {
			mvc.perform(call.header("Authorization", "Bearer " + ghost))
				.andExpect(status().isUnauthorized())
				.andExpect(jsonPath("$.error.code").value("UNAUTHORIZED"));
		}
		for (MockHttpServletRequestBuilder call : ownerCalls()) {
			mvc.perform(call.header("Authorization", "Bearer " + noBusiness.token()))
				.andExpect(status().isNotFound())
				.andExpect(jsonPath("$.error.code").value("BUSINESS_NOT_FOUND"));
		}
	}

	private static List<MockHttpServletRequestBuilder> ownerCalls() {
		return List.of(get("/business/products").contentType(MediaType.APPLICATION_JSON),
				post("/business/products").contentType(MediaType.APPLICATION_JSON)
					.content("{\"name\":\"A\",\"priceCents\":1}"),
				patch("/business/products/x").contentType(MediaType.APPLICATION_JSON).content("{}"),
				delete("/business/products/x").contentType(MediaType.APPLICATION_JSON),
				post("/business/products/x/stock").contentType(MediaType.APPLICATION_JSON)
					.content("{\"delta\":1,\"reason\":\"r\"}"),
				get("/business/inventory/low").contentType(MediaType.APPLICATION_JSON),
				get("/business/sales/summary").contentType(MediaType.APPLICATION_JSON));
	}

	// ---- GET /business/products

	@Test
	void listReturnsOnlyOwnProductsIncludingInactive() throws Exception {
		Owner a = ownerWithBusiness("lista");
		Owner b = ownerWithBusiness("listb");
		String active = createProduct(a, "{\"name\":\"Uno\",\"priceCents\":1}");
		String inactive = createProduct(a, "{\"name\":\"Dos\",\"priceCents\":2}");
		String other = createProduct(b, "{\"name\":\"Ajeno\",\"priceCents\":3}");
		mvc.perform(authDelete(a, "/business/products/" + inactive)).andExpect(status().isOk());
		mvc.perform(authGet(a, "/business/products"))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.length()").value(2))
			.andExpect(jsonPath("$[0].id").value(active))
			.andExpect(jsonPath("$[1].id").value(inactive))
			.andExpect(jsonPath("$[1].active").value(false));
		assertThat(other).isNotBlank();
	}

	// ---- PATCH /business/products/{id}

	@Test
	void patchUpdatesOnlySentFieldsAndNullClearsOptionals() throws Exception {
		Owner o = ownerWithBusiness("patch");
		String id = createProduct(o, "{\"name\":\"Taco\",\"priceCents\":2500,\"prepMinutes\":5,"
				+ "\"imageUrl\":\"https://x.mx/t.png\"}");
		mvc.perform(authPatch(o, "/business/products/" + id, "{\"name\":\" Taco al pastor \",\"priceCents\":3000}"))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.name").value("Taco al pastor"))
			.andExpect(jsonPath("$.priceCents").value(3000))
			.andExpect(jsonPath("$.prepMinutes").value(5))
			.andExpect(jsonPath("$.imageUrl").value("https://x.mx/t.png"));
		mvc.perform(authPatch(o, "/business/products/" + id, "{\"prepMinutes\":null,\"imageUrl\":null,\"active\":false,"
				+ "\"trackStock\":false}"))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.prepMinutes").value(org.hamcrest.Matchers.nullValue()))
			.andExpect(jsonPath("$.imageUrl").value(org.hamcrest.Matchers.nullValue()))
			.andExpect(jsonPath("$.active").value(false))
			.andExpect(jsonPath("$.trackStock").value(false))
			.andExpect(jsonPath("$.name").value("Taco al pastor"));
		mvc.perform(authPatch(o, "/business/products/" + id, "{}")).andExpect(status().isOk());
	}

	@Test
	void patchValidationErrorsLeaveTheProductUntouched() throws Exception {
		Owner o = ownerWithBusiness("patchval");
		String id = createProduct(o, "{\"name\":\"Taco\",\"priceCents\":2500,\"stock\":4}");
		expectPatchError(o, id, "{\"name\":null}", "name: must be a string");
		expectPatchError(o, id, "{\"name\":\" \"}", "name: is required");
		expectPatchError(o, id, "{\"priceCents\":null}", "priceCents: must be a non-negative integer");
		expectPatchError(o, id, "{\"priceCents\":-5}", "priceCents: must be a non-negative integer");
		expectPatchError(o, id, "{\"stock\":-1}", "stock: must be a non-negative integer");
		expectPatchError(o, id, "{\"prepMinutes\":-2}", "prepMinutes: must be a positive integer");
		expectPatchError(o, id, "{\"active\":\"no\"}", "active: must be a boolean");
		expectPatchError(o, id, "{\"name\":\"Nuevo\",\"stock\":-1}", "stock: must be a non-negative integer");
		var row = jdbc.queryForMap("SELECT name, price_cents, stock FROM products WHERE id=?", id);
		assertThat(row.get("name")).isEqualTo("Taco");
		assertThat(row.get("price_cents")).isEqualTo(2500L);
		assertThat(row.get("stock")).isEqualTo(4);
	}

	@Test
	void patchStockLogsAManualEditMovementWithTheRealDelta() throws Exception {
		Owner o = ownerWithBusiness("patchstock");
		String id = createProduct(o, "{\"name\":\"Taco\",\"priceCents\":100,\"stock\":10}");
		mvc.perform(authPatch(o, "/business/products/" + id, "{\"stock\":7}"))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.stock").value(7));
		// same value: nothing to log
		mvc.perform(authPatch(o, "/business/products/" + id, "{\"stock\":7}")).andExpect(status().isOk());
		mvc.perform(authPatch(o, "/business/products/" + id, "{\"stock\":20}")).andExpect(status().isOk());
		List<Integer> deltas = jdbc.queryForList(
				"SELECT delta FROM stock_movements WHERE product_id=? AND reason='manual_edit' ORDER BY id",
				Integer.class, id);
		assertThat(deltas).containsExactly(-3, 13);
		assertThat(jdbc.queryForObject("SELECT SUM(delta) FROM stock_movements WHERE product_id=?", Integer.class,
				id))
			.isEqualTo(20);
	}

	@Test
	void patchAndDeleteOfAnotherOwnersOrUnknownProductAre404() throws Exception {
		Owner a = ownerWithBusiness("isoa");
		Owner b = ownerWithBusiness("isob");
		String id = createProduct(a, "{\"name\":\"Mio\",\"priceCents\":100,\"stock\":3}");
		mvc.perform(authPatch(b, "/business/products/" + id, "{\"name\":\"Robado\",\"stock\":99}"))
			.andExpect(status().isNotFound())
			.andExpect(jsonPath("$.error.code").value("PRODUCT_NOT_FOUND"));
		mvc.perform(authDelete(b, "/business/products/" + id))
			.andExpect(status().isNotFound())
			.andExpect(jsonPath("$.error.code").value("PRODUCT_NOT_FOUND"));
		mvc.perform(authPatch(a, "/business/products/no-such-id", "{}"))
			.andExpect(status().isNotFound())
			.andExpect(jsonPath("$.error.code").value("PRODUCT_NOT_FOUND"));
		var row = jdbc.queryForMap("SELECT name, stock, active FROM products WHERE id=?", id);
		assertThat(row.get("name")).isEqualTo("Mio");
		assertThat(row.get("stock")).isEqualTo(3);
		assertThat(row.get("active")).isEqualTo(true);
		assertThat(movementCount(id)).isEqualTo(1);
	}

	// ---- DELETE /business/products/{id}

	@Test
	void deleteIsASoftDeleteThatHidesFromTheCatalogAndIsIdempotent() throws Exception {
		Owner o = ownerWithBusiness("del");
		String id = createProduct(o, "{\"name\":\"Taco\",\"priceCents\":100,\"stock\":2}");
		mvc.perform(get("/businesses/" + o.businessId() + "/products"))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.length()").value(1));
		for (int i = 0; i < 2; i++) {
			mvc.perform(authDelete(o, "/business/products/" + id))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.id").value(id))
				.andExpect(jsonPath("$.active").value(false));
		}
		assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM products WHERE id=?", Integer.class, id)).isEqualTo(1);
		assertThat(movementCount(id)).isEqualTo(1);
		mvc.perform(get("/businesses/" + o.businessId() + "/products"))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.length()").value(0));
	}

	// ---- POST /business/products/{id}/stock

	@Test
	void stockAdjustmentReturnsFlatProductPlusNestedAndLogsTheMovement() throws Exception {
		Owner o = ownerWithBusiness("stock");
		String id = createProduct(o, "{\"name\":\"Taco\",\"priceCents\":100,\"stock\":5}");
		long before = Instant.now().getEpochSecond();
		var res = mvc.perform(authPost(o, "/business/products/" + id + "/stock",
				"{\"delta\":-2,\"reason\":\"  merma  \"}"))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.id").value(id))
			.andExpect(jsonPath("$.stock").value(3))
			.andExpect(jsonPath("$.name").value("Taco"))
			.andExpect(jsonPath("$.product.id").value(id))
			.andExpect(jsonPath("$.product.stock").value(3))
			.andExpect(jsonPath("$.movement.id").value(org.hamcrest.Matchers.matchesPattern(ULID)))
			.andExpect(jsonPath("$.movement.productId").value(id))
			.andExpect(jsonPath("$.movement.delta").value(-2))
			.andExpect(jsonPath("$.movement.reason").value("merma"))
			.andReturn();
		JsonNode body = json.readTree(res.getResponse().getContentAsString());
		assertThat(body.at("/movement/createdAt").asLong()).isBetween(before, Instant.now().getEpochSecond() + 1);
		mvc.perform(authPost(o, "/business/products/" + id + "/stock", "{\"delta\":10,\"reason\":\"compra\"}"))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.stock").value(13));
		var movement = jdbc.queryForMap("SELECT delta, reason FROM stock_movements WHERE id=?",
				body.at("/movement/id").asString());
		assertThat(movement.get("delta")).isEqualTo(-2);
		assertThat(movement.get("reason")).isEqualTo("merma");
		assertThat(jdbc.queryForObject("SELECT stock FROM products WHERE id=?", Integer.class, id)).isEqualTo(13);
	}

	@Test
	void stockCannotGoNegativeAndFailureLeavesNoTrace() throws Exception {
		Owner o = ownerWithBusiness("neg");
		String id = createProduct(o, "{\"name\":\"Taco\",\"priceCents\":100,\"stock\":2}");
		mvc.perform(authPost(o, "/business/products/" + id + "/stock", "{\"delta\":-3,\"reason\":\"x\"}"))
			.andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.error.code").value("INSUFFICIENT_STOCK"));
		// exactly to zero is fine
		mvc.perform(authPost(o, "/business/products/" + id + "/stock", "{\"delta\":-2,\"reason\":\"x\"}"))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.stock").value(0));
		assertThat(movementCount(id)).isEqualTo(2); // initial + the successful one
	}

	@Test
	void stockDeltaThatWouldOverflowIsRejectedWithoutTouchingTheRow() throws Exception {
		Owner o = ownerWithBusiness("ovf");
		String id = createProduct(o, "{\"name\":\"Taco\",\"priceCents\":100,\"stock\":5}");
		mvc.perform(authPost(o, "/business/products/" + id + "/stock", "{\"delta\":2147483647,\"reason\":\"x\"}"))
			.andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.error.code").value("VALIDATION_ERROR"));
		mvc.perform(authPost(o, "/business/products/" + id + "/stock", "{\"delta\":-2147483648,\"reason\":\"x\"}"))
			.andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.error.code").value("INSUFFICIENT_STOCK"));
		assertThat(jdbc.queryForObject("SELECT stock FROM products WHERE id=?", Integer.class, id)).isEqualTo(5);
		assertThat(movementCount(id)).isEqualTo(1);
	}

	@Test
	void stockValidationAndOwnership() throws Exception {
		Owner a = ownerWithBusiness("stocka");
		Owner b = ownerWithBusiness("stockb");
		String id = createProduct(a, "{\"name\":\"Taco\",\"priceCents\":100,\"stock\":5}");
		expectStockError(a, id, "{\"reason\":\"x\"}", "delta: is required");
		expectStockError(a, id, "{\"delta\":1.5,\"reason\":\"x\"}", "delta: must be an integer");
		expectStockError(a, id, "{\"delta\":\"1\",\"reason\":\"x\"}", "delta: must be an integer");
		expectStockError(a, id, "{\"delta\":1}", "reason: is required");
		expectStockError(a, id, "{\"delta\":1,\"reason\":\"  \"}", "reason: is required");
		mvc.perform(authPost(b, "/business/products/" + id + "/stock", "{\"delta\":1,\"reason\":\"x\"}"))
			.andExpect(status().isNotFound())
			.andExpect(jsonPath("$.error.code").value("PRODUCT_NOT_FOUND"));
		mvc.perform(authPost(a, "/business/products/nope/stock", "{\"delta\":1,\"reason\":\"x\"}"))
			.andExpect(status().isNotFound());
		assertThat(jdbc.queryForObject("SELECT stock FROM products WHERE id=?", Integer.class, id)).isEqualTo(5);
		assertThat(movementCount(id)).isEqualTo(1);
	}

	@Test
	void concurrentDecrementsNeverOversell() throws Exception {
		Owner o = ownerWithBusiness("race");
		String id = createProduct(o, "{\"name\":\"Taco\",\"priceCents\":100,\"stock\":5}");
		int threads = 12;
		ExecutorService pool = Executors.newFixedThreadPool(threads);
		CountDownLatch start = new CountDownLatch(1);
		List<Future<Integer>> results = new ArrayList<>();
		try {
			for (int i = 0; i < threads; i++) {
				results.add(pool.submit(() -> {
					start.await();
					return mvc.perform(authPost(o, "/business/products/" + id + "/stock",
							"{\"delta\":-1,\"reason\":\"venta\"}"))
						.andReturn()
						.getResponse()
						.getStatus();
				}));
			}
			start.countDown();
			int ok = 0;
			int rejected = 0;
			for (Future<Integer> f : results) {
				int code = f.get();
				if (code == 200) {
					ok++;
				}
				else if (code == 400) {
					rejected++;
				}
			}
			assertThat(ok).isEqualTo(5);
			assertThat(rejected).isEqualTo(threads - 5);
		}
		finally {
			pool.shutdownNow();
		}
		assertThat(jdbc.queryForObject("SELECT stock FROM products WHERE id=?", Integer.class, id)).isZero();
		assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM stock_movements WHERE product_id=? AND reason='venta'",
				Integer.class, id))
			.isEqualTo(5);
	}

	// ---- GET /business/inventory/low

	@Test
	void lowStockListsTrackedActiveProductsAtOrBelowThresholdSortedByStock() throws Exception {
		Owner a = ownerWithBusiness("lowa");
		Owner b = ownerWithBusiness("lowb");
		String s5 = createProduct(a, "{\"name\":\"Cinco\",\"priceCents\":1,\"stock\":5}");
		String s0 = createProduct(a, "{\"name\":\"Cero\",\"priceCents\":1,\"stock\":0}");
		String s6 = createProduct(a, "{\"name\":\"Seis\",\"priceCents\":1,\"stock\":6}");
		String s2 = createProduct(a, "{\"name\":\"Dos\",\"priceCents\":1,\"stock\":2}");
		String untracked = createProduct(a, "{\"name\":\"Sin control\",\"priceCents\":1,\"trackStock\":false}");
		String inactive = createProduct(a, "{\"name\":\"Baja\",\"priceCents\":1,\"stock\":1}");
		String other = createProduct(b, "{\"name\":\"Ajeno\",\"priceCents\":1,\"stock\":1}");
		mvc.perform(authDelete(a, "/business/products/" + inactive)).andExpect(status().isOk());

		mvc.perform(authGet(a, "/business/inventory/low"))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.length()").value(3))
			.andExpect(jsonPath("$[0].id").value(s0))
			.andExpect(jsonPath("$[1].id").value(s2))
			.andExpect(jsonPath("$[2].id").value(s5));
		mvc.perform(authGet(a, "/business/inventory/low?threshold=0"))
			.andExpect(jsonPath("$.length()").value(1))
			.andExpect(jsonPath("$[0].id").value(s0));
		mvc.perform(authGet(a, "/business/inventory/low?threshold=6"))
			.andExpect(jsonPath("$.length()").value(4));
		mvc.perform(authGet(a, "/business/inventory/low?threshold="))
			.andExpect(jsonPath("$.length()").value(3));
		assertThat(List.of(s6, untracked, other)).doesNotContainNull();
	}

	@Test
	void lowStockRejectsABadThreshold() throws Exception {
		Owner o = ownerWithBusiness("lowbad");
		for (String bad : List.of("abc", "-1", "1.5", "99999999999")) {
			mvc.perform(authGet(o, "/business/inventory/low?threshold=" + bad))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.error.code").value("VALIDATION_ERROR"))
				.andExpect(jsonPath("$.error.message").value("threshold: must be a non-negative integer"));
		}
	}

	// ---- helpers

	private int movementCount(String productId) {
		return jdbc.queryForObject("SELECT COUNT(*) FROM stock_movements WHERE product_id=?", Integer.class,
				productId);
	}

	private Owner signup(String label) {
		try {
			String email = label + "@prod-test.mx";
			var res = mvc.perform(post("/auth/register").contentType(MediaType.APPLICATION_JSON)
				.content("{\"email\":\"" + email + "\",\"password\":\"password-1\",\"name\":\"" + label + "\"}"))
				.andExpect(status().isCreated())
				.andReturn();
			JsonNode body = json.readTree(res.getResponse().getContentAsString());
			return new Owner(body.at("/user/id").asString(), body.get("token").asString(), null);
		}
		catch (Exception ex) {
			throw new IllegalStateException(ex);
		}
	}

	private Owner ownerWithBusiness(String label) throws Exception {
		Owner o = signup(label);
		var res = mvc.perform(authPost(o, "/me/business", "{\"name\":\"Negocio " + label
				+ "\",\"category\":\"food\",\"prepType\":\"instant\"}"))
			.andExpect(status().isCreated())
			.andReturn();
		String businessId = json.readTree(res.getResponse().getContentAsString()).get("id").asString();
		return new Owner(o.id(), o.token(), businessId);
	}

	private String createProduct(Owner o, String body) throws Exception {
		var res = mvc.perform(authPost(o, "/business/products", body)).andExpect(status().isCreated()).andReturn();
		return json.readTree(res.getResponse().getContentAsString()).get("id").asString();
	}

	private String token(String subject) throws Exception {
		var claims = new JWTClaimsSet.Builder().subject(subject)
			.claim("email", "ghost@prod-test.mx")
			.issueTime(new Date())
			.expirationTime(new Date(System.currentTimeMillis() + 3_600_000))
			.build();
		var jwt = new SignedJWT(new JWSHeader(JWSAlgorithm.HS256), claims);
		jwt.sign(new MACSigner(SECRET.getBytes(StandardCharsets.UTF_8)));
		return jwt.serialize();
	}

	private static MockHttpServletRequestBuilder authPost(Owner o, String url, String body) {
		return post(url).header("Authorization", "Bearer " + o.token())
			.contentType(MediaType.APPLICATION_JSON)
			.content(body);
	}

	private static MockHttpServletRequestBuilder authPatch(Owner o, String url, String body) {
		return patch(url).header("Authorization", "Bearer " + o.token())
			.contentType(MediaType.APPLICATION_JSON)
			.content(body);
	}

	private static MockHttpServletRequestBuilder authGet(Owner o, String url) {
		return get(url).header("Authorization", "Bearer " + o.token());
	}

	private static MockHttpServletRequestBuilder authDelete(Owner o, String url) {
		return delete(url).header("Authorization", "Bearer " + o.token());
	}

	private void expectCreateError(Owner o, String body, String message) throws Exception {
		mvc.perform(authPost(o, "/business/products", body))
			.andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.error.code").value("VALIDATION_ERROR"))
			.andExpect(jsonPath("$.error.message").value(message));
	}

	private void expectPatchError(Owner o, String id, String body, String message) throws Exception {
		mvc.perform(authPatch(o, "/business/products/" + id, body))
			.andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.error.code").value("VALIDATION_ERROR"))
			.andExpect(jsonPath("$.error.message").value(message));
	}

	private void expectStockError(Owner o, String id, String body, String message) throws Exception {
		mvc.perform(authPost(o, "/business/products/" + id + "/stock", body))
			.andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.error.code").value("VALIDATION_ERROR"))
			.andExpect(jsonPath("$.error.message").value(message));
	}

}
