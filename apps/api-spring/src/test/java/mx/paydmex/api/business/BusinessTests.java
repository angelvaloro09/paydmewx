package mx.paydmex.api.business;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Date;

import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.MACSigner;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;

import mx.paydmex.api.common.AppException;
import mx.paydmex.api.common.Clabe;
import mx.paydmex.api.pey.FakePeyClient;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(FakePeyClient.Config.class)
class BusinessTests {

	private static final String SECRET = "unit-test-only-hs256-key-0123456789-abcdef";

	private static final String GOOD_CLABE = "012180015826225713";

	private static final String BAD_CLABE = "012180015826225719";

	@Autowired
	MockMvc mvc;

	@Autowired
	JdbcTemplate jdbc;

	@Autowired
	FakePeyClient pey;

	private final JsonMapper json = JsonMapper.builder().build();

	record Owner(String id, String token) {
	}

	@BeforeEach
	void resetFake() {
		pey.reset();
	}

	@AfterEach
	void cleanup() {
		String owners = "(SELECT id FROM users WHERE email LIKE '%@biz-test.mx')";
		jdbc.update("DELETE FROM products WHERE business_id IN (SELECT id FROM businesses WHERE owner_id IN "
				+ owners + ")");
		jdbc.update("DELETE FROM businesses WHERE owner_id IN " + owners);
		jdbc.update("DELETE FROM users WHERE email LIKE '%@biz-test.mx'");
	}

	// ---- POST /me/business

	@Test
	void createReturnsContractShapeAndOwnerView() throws Exception {
		Owner o = signup("shape");
		long before = Instant.now().getEpochSecond();
		ResultActions res = mvc.perform(createBusiness(o, """
				{"name":"  Tacos Don Carlos ","category":"food","prepType":"made_to_order",
				 "description":"Al pastor","address":"Calle 1","lat":19.43,"lng":-99.13}"""))
			.andExpect(status().isCreated())
			.andExpect(jsonPath("$.name").value("Tacos Don Carlos"))
			.andExpect(jsonPath("$.ownerId").value(o.id()))
			.andExpect(jsonPath("$.category").value("food"))
			.andExpect(jsonPath("$.prepType").value("made_to_order"))
			.andExpect(jsonPath("$.lat").value(19.43))
			.andExpect(jsonPath("$.active").value(true))
			.andExpect(jsonPath("$.clabe").doesNotExist())
			.andExpect(jsonPath("$.peyBankAccountId").doesNotExist())
			.andExpect(jsonPath("$.id").value(org.hamcrest.Matchers.matchesPattern("[0-9A-HJKMNP-TV-Z]{26}")));
		JsonNode body = json.readTree(res.andReturn().getResponse().getContentAsString());
		assertThat(body.get("createdAt").asLong()).isBetween(before, Instant.now().getEpochSecond() + 1);
		// GET /me now carries the business
		mvc.perform(get("/me").header("Authorization", "Bearer " + o.token()))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.business.id").value(body.get("id").asString()));
	}

	@Test
	void createTwiceIs409() throws Exception {
		Owner o = signup("twice");
		mvc.perform(createBusiness(o, minimal())).andExpect(status().isCreated());
		mvc.perform(createBusiness(o, minimal()))
			.andExpect(status().isConflict())
			.andExpect(jsonPath("$.error.code").value("BUSINESS_ALREADY_EXISTS"));
		assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM businesses WHERE owner_id=?", Integer.class, o.id()))
			.isEqualTo(1);
	}

	@Test
	void createValidationErrors() throws Exception {
		Owner o = signup("val");
		expectCreateError(o, "{\"category\":\"food\",\"prepType\":\"instant\"}", "name: is required");
		expectCreateError(o, "{\"name\":\"   \",\"category\":\"food\",\"prepType\":\"instant\"}",
				"name: is required");
		expectCreateError(o, "{\"name\":\"A\",\"prepType\":\"instant\"}", "category: is required");
		expectCreateError(o, "{\"name\":\"A\",\"category\":\"cars\",\"prepType\":\"instant\"}",
				"category: " + BusinessTaxonomy.CATEGORY_MESSAGE);
		expectCreateError(o, "{\"name\":\"A\",\"category\":\"food\",\"prepType\":\"slow\"}",
				"prepType: " + BusinessTaxonomy.PREP_TYPE_MESSAGE);
		expectCreateError(o, "{\"name\":\"A\",\"category\":\"food\",\"prepType\":\"instant\",\"lat\":91}",
				"lat: must be between -90 and 90");
		assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM businesses WHERE owner_id=?", Integer.class, o.id()))
			.isZero();
	}

	@Test
	void createRequiresAuthAndAnExistingUser() throws Exception {
		mvc.perform(post("/me/business").contentType(MediaType.APPLICATION_JSON).content(minimal()))
			.andExpect(status().isUnauthorized());
		// valid signature, user that does not exist: 401 UNAUTHORIZED (same as /me), not 409/500
		String ghost = token("ghost-" + System.nanoTime());
		mvc.perform(post("/me/business").header("Authorization", "Bearer " + ghost)
			.contentType(MediaType.APPLICATION_JSON)
			.content(minimal()))
			.andExpect(status().isUnauthorized())
			.andExpect(jsonPath("$.error.code").value("UNAUTHORIZED"));
	}

	// ---- PATCH /me/business

	@Test
	void patchUpdatesOnlyGivenFieldsAndNullClears() throws Exception {
		Owner o = signup("patch");
		mvc.perform(createBusiness(o, """
				{"name":"Old","category":"food","prepType":"instant","description":"d","address":"a","lat":1,"lng":2}"""))
			.andExpect(status().isCreated());
		mvc.perform(patchBusiness(o, """
				{"name":" New ","category":"services","description":null,"lat":null,"active":false}"""))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.name").value("New"))
			.andExpect(jsonPath("$.category").value("services"))
			.andExpect(jsonPath("$.prepType").value("instant"))
			.andExpect(jsonPath("$.description").doesNotExist())
			.andExpect(jsonPath("$.lat").doesNotExist())
			.andExpect(jsonPath("$.address").value("a"))
			.andExpect(jsonPath("$.lng").value(2.0))
			.andExpect(jsonPath("$.active").value(false));
	}

	@Test
	void patchEmptyBodyIsANoOp() throws Exception {
		Owner o = signup("noop");
		mvc.perform(createBusiness(o, minimal())).andExpect(status().isCreated());
		mvc.perform(patchBusiness(o, "{}"))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.name").value("Negocio"));
	}

	@Test
	void patchWithoutBusinessIs404() throws Exception {
		Owner o = signup("nobiz");
		mvc.perform(patchBusiness(o, "{\"name\":\"X\"}"))
			.andExpect(status().isNotFound())
			.andExpect(jsonPath("$.error.code").value("BUSINESS_NOT_FOUND"));
	}

	@Test
	void patchValidationErrors() throws Exception {
		Owner o = signup("pval");
		mvc.perform(createBusiness(o, minimal())).andExpect(status().isCreated());
		expectPatchError(o, "{\"name\":\"  \"}", "name: is required");
		expectPatchError(o, "{\"name\":5}", "name: must be a string");
		expectPatchError(o, "{\"category\":\"cars\"}", "category: " + BusinessTaxonomy.CATEGORY_MESSAGE);
		expectPatchError(o, "{\"prepType\":null}", "prepType: must be a string");
		expectPatchError(o, "{\"active\":\"yes\"}", "active: must be a boolean");
		expectPatchError(o, "{\"lng\":181}", "lng: must be between -180 and 180");
		expectPatchError(o, "{\"clabe\":null}", "clabe: must be a string");
		expectPatchError(o, "[]", "body: must be a JSON object");
		mvc.perform(patch("/me/business").header("Authorization", "Bearer " + o.token())
			.contentType(MediaType.APPLICATION_JSON)
			.content("{not json"))
			.andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.error.code").value("BAD_REQUEST"));
	}

	@Test
	void patchInvalidClabeIs400AndPeyIsNotCalled() throws Exception {
		Owner o = signup("badclabe");
		mvc.perform(createBusiness(o, minimal())).andExpect(status().isCreated());
		mvc.perform(patchBusiness(o, "{\"clabe\":\"" + BAD_CLABE + "\"}"))
			.andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.error.code").value("INVALID_CLABE"));
		mvc.perform(patchBusiness(o, "{\"clabe\":\"1234\"}")).andExpect(status().isBadRequest());
		assertThat(pey.calls).isEmpty();
	}

	@Test
	void patchValidClabeRegistersWithPeyAndStoresIt() throws Exception {
		Owner o = signup("clabe");
		mvc.perform(createBusiness(o, minimal())).andExpect(status().isCreated());
		mvc.perform(patchBusiness(o, "{\"name\":\"Tacos Oficial\",\"clabe\":\"" + GOOD_CLABE + "\"}"))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.name").value("Tacos Oficial"))
			.andExpect(jsonPath("$.clabe").value(GOOD_CLABE))
			.andExpect(jsonPath("$.peyBankAccountId").value("ba_fake_1"))
			.andExpect(jsonPath("$.codiStatus").value("PENDING"));
		assertThat(pey.calls).containsExactly(new FakePeyClient.Call("Tacos Oficial", "Tacos Oficial", GOOD_CLABE));
		mvc.perform(get("/me").header("Authorization", "Bearer " + o.token()))
			.andExpect(jsonPath("$.business.clabe").value(GOOD_CLABE))
			.andExpect(jsonPath("$.business.peyBankAccountId").value("ba_fake_1"));
	}

	@Test
	void patchSameClabeAgainDoesNotCallPeyTwiceButNewClabeDoes() throws Exception {
		Owner o = signup("reclabe");
		mvc.perform(createBusiness(o, minimal())).andExpect(status().isCreated());
		mvc.perform(patchBusiness(o, "{\"clabe\":\"" + GOOD_CLABE + "\"}")).andExpect(status().isOk());
		mvc.perform(patchBusiness(o, "{\"clabe\":\"" + GOOD_CLABE + "\",\"address\":\"x\"}"))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.address").value("x"))
			.andExpect(jsonPath("$.peyBankAccountId").value("ba_fake_1"));
		assertThat(pey.calls).hasSize(1);

		String other = validClabeOtherThan(GOOD_CLABE);
		mvc.perform(patchBusiness(o, "{\"clabe\":\"" + other + "\"}"))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.clabe").value(other))
			.andExpect(jsonPath("$.peyBankAccountId").value("ba_fake_2"));
	}

	@Test
	void peyFailureLeavesNothingStored() throws Exception {
		Owner o = signup("peyfail");
		mvc.perform(createBusiness(o, minimal())).andExpect(status().isCreated());
		pey.failure = new AppException(HttpStatus.BAD_GATEWAY, "PEY_ERROR", "boom [req-1]");
		mvc.perform(patchBusiness(o, "{\"name\":\"Changed\",\"clabe\":\"" + GOOD_CLABE + "\"}"))
			.andExpect(status().isBadGateway())
			.andExpect(jsonPath("$.error.code").value("PEY_ERROR"));
		pey.failure = new AppException(HttpStatus.SERVICE_UNAVAILABLE, "PEY_NOT_CONFIGURED", "not configured");
		mvc.perform(patchBusiness(o, "{\"clabe\":\"" + GOOD_CLABE + "\"}"))
			.andExpect(status().isServiceUnavailable())
			.andExpect(jsonPath("$.error.code").value("PEY_NOT_CONFIGURED"));
		mvc.perform(get("/me").header("Authorization", "Bearer " + o.token()))
			.andExpect(jsonPath("$.business.name").value("Negocio"))
			.andExpect(jsonPath("$.business.clabe").doesNotExist())
			.andExpect(jsonPath("$.business.peyBankAccountId").doesNotExist());
	}

	// ---- public discovery

	@Test
	void discoveryListsOnlyActiveAndNeverLeaksBankData() throws Exception {
		Owner a = signup("pub-a");
		Owner b = signup("pub-b");
		String idA = createAndGetId(a, "{\"name\":\"Tacos Don Carlos\",\"category\":\"food\",\"prepType\":\"made_to_order\","
				+ "\"description\":\"Pastor y suadero\",\"address\":\"Roma Norte\"}");
		String idB = createAndGetId(b, "{\"name\":\"Zapatos Lupe\",\"category\":\"footwear\",\"prepType\":\"instant\"}");
		mvc.perform(patchBusiness(a, "{\"clabe\":\"" + GOOD_CLABE + "\"}")).andExpect(status().isOk());

		mvc.perform(get("/businesses"))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$[?(@.id=='" + idA + "')].clabe").isEmpty())
			.andExpect(jsonPath("$[?(@.id=='" + idA + "')].peyBankAccountId").isEmpty())
			.andExpect(jsonPath("$[?(@.id=='" + idA + "')].codiStatus").value(org.hamcrest.Matchers.contains("PENDING")))
			.andExpect(jsonPath("$[?(@.id=='" + idB + "')].name").value(org.hamcrest.Matchers.contains("Zapatos Lupe")));
		mvc.perform(get("/businesses/" + idA))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.name").value("Tacos Don Carlos"))
			.andExpect(jsonPath("$.clabe").doesNotExist())
			.andExpect(jsonPath("$.peyBankAccountId").doesNotExist());

		// deactivated business disappears from list, detail and products
		jdbc.update("UPDATE businesses SET active = FALSE WHERE id = ?", idB);
		mvc.perform(get("/businesses")).andExpect(jsonPath("$[?(@.id=='" + idB + "')]").isEmpty());
		mvc.perform(get("/businesses/" + idB))
			.andExpect(status().isNotFound())
			.andExpect(jsonPath("$.error.code").value("BUSINESS_NOT_FOUND"));
		mvc.perform(get("/businesses/" + idB + "/products")).andExpect(status().isNotFound());
		mvc.perform(get("/businesses/does-not-exist")).andExpect(status().isNotFound());
	}

	@Test
	void discoveryFilters() throws Exception {
		Owner a = signup("flt-a");
		Owner b = signup("flt-b");
		String idA = createAndGetId(a, "{\"name\":\"Tacos Don Carlos\",\"category\":\"food\",\"prepType\":\"made_to_order\","
				+ "\"description\":\"Pastor 100% casero\",\"address\":\"Roma Norte\"}");
		String idB = createAndGetId(b, "{\"name\":\"Zapatos Lupe\",\"category\":\"footwear\",\"prepType\":\"instant\"}");

		assertIds("/businesses?category=food", idA, idB, true, false);
		assertIds("/businesses?prepType=instant", idA, idB, false, true);
		assertIds("/businesses?category=food&prepType=instant", idA, idB, false, false);
		assertIds("/businesses?q=TACOS", idA, idB, true, false); // case-insensitive, name
		assertIds("/businesses?q=roma", idA, idB, true, false); // address
		assertIds("/businesses?q=suadero", idA, idB, false, false);
		assertIds("/businesses?q=casero", idA, idB, true, false); // description
		assertIds(get("/businesses").param("q", "100%"), idA, idB, true, false); // literal %
		assertIds(get("/businesses").param("q", "%"), idA, idB, true, false); // only the business that has a %
		assertIds(get("/businesses").param("q", "_"), idA, idB, false, false); // lone _ is not a wildcard
		assertIds(get("/businesses").param("category", "").param("q", ""), idA, idB, true, true); // blank = ignored
		mvc.perform(get("/businesses?category=cars"))
			.andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.error.message").value("category: " + BusinessTaxonomy.CATEGORY_MESSAGE));
		mvc.perform(get("/businesses?prepType=slow")).andExpect(status().isBadRequest());
	}

	@Test
	void businessProductsListsOnlyActiveWithContractShape() throws Exception {
		Owner o = signup("prod");
		String id = createAndGetId(o, minimal());
		insertProduct("01PRODUCT0000000000000001A", id, "Taco", 2500, true, 10, null, null, true);
		insertProduct("01PRODUCT0000000000000002B", id, "Agua", 1500, false, 0, 5, "http://img/agua.png", true);
		insertProduct("01PRODUCT0000000000000003C", id, "Viejo", 100, true, 1, null, null, false);

		mvc.perform(get("/businesses/" + id + "/products"))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.length()").value(2))
			.andExpect(jsonPath("$[0].id").value("01PRODUCT0000000000000001A"))
			.andExpect(jsonPath("$[0].businessId").value(id))
			.andExpect(jsonPath("$[0].priceCents").value(2500))
			.andExpect(jsonPath("$[0].trackStock").value(true))
			.andExpect(jsonPath("$[0].stock").value(10))
			.andExpect(jsonPath("$[0].prepMinutes").doesNotExist())
			.andExpect(jsonPath("$[0].active").value(true))
			.andExpect(jsonPath("$[1].name").value("Agua"))
			.andExpect(jsonPath("$[1].prepMinutes").value(5))
			.andExpect(jsonPath("$[1].imageUrl").value("http://img/agua.png"));
	}

	// ---- taxonomy vs V1 CHECK constraints

	@Test
	void taxonomyMatchesTheDatabaseChecks() {
		Owner o = signup("tax");
		String sql = "INSERT INTO businesses (id, owner_id, name, category, prep_type, active, created_at) "
				+ "VALUES (?, ?, 'T', ?, ?, TRUE, 1)";
		for (String category : BusinessTaxonomy.CATEGORIES) {
			jdbc.update(sql, "tax-" + category, o.id(), category, "instant");
			jdbc.update("DELETE FROM businesses WHERE id = ?", "tax-" + category);
		}
		for (String prepType : BusinessTaxonomy.PREP_TYPES) {
			jdbc.update(sql, "tax-" + prepType, o.id(), "food", prepType);
			jdbc.update("DELETE FROM businesses WHERE id = ?", "tax-" + prepType);
		}
		assertThat(BusinessTaxonomy.CATEGORIES).hasSize(8);
		assertThat(BusinessTaxonomy.PREP_TYPES).hasSize(2);
		// the CHECK rejects anything outside the sets, so a value added only on one side is caught
		assertThatThrownBy(() -> jdbc.update(sql, "tax-bad", o.id(), "cars", "instant"))
			.isInstanceOf(DataIntegrityViolationException.class);
		assertThatThrownBy(() -> jdbc.update(sql, "tax-bad", o.id(), "food", "slow"))
			.isInstanceOf(DataIntegrityViolationException.class);
	}

	@Test
	void clabeValidatorMatchesNodeVectors() {
		assertThat(Clabe.isValid(GOOD_CLABE)).isTrue();
		assertThat(Clabe.isValid(BAD_CLABE)).isFalse();
		assertThat(Clabe.isValid("12345")).isFalse();
		assertThat(Clabe.isValid("01218001582622571x")).isFalse();
		assertThat(Clabe.isValid(null)).isFalse();
	}

	// ---- helpers

	private Owner signup(String label) {
		try {
			String email = label + "@biz-test.mx";
			var res = mvc.perform(post("/auth/register").contentType(MediaType.APPLICATION_JSON)
				.content("{\"email\":\"" + email + "\",\"password\":\"password-1\",\"name\":\"" + label + "\"}"))
				.andExpect(status().isCreated())
				.andReturn();
			JsonNode body = json.readTree(res.getResponse().getContentAsString());
			return new Owner(body.at("/user/id").asString(), body.get("token").asString());
		}
		catch (Exception ex) {
			throw new IllegalStateException(ex);
		}
	}

	private String token(String subject) throws Exception {
		var claims = new JWTClaimsSet.Builder().subject(subject)
			.claim("email", "ghost@biz-test.mx")
			.issueTime(new Date())
			.expirationTime(new Date(System.currentTimeMillis() + 3_600_000))
			.build();
		var jwt = new SignedJWT(new JWSHeader(JWSAlgorithm.HS256), claims);
		jwt.sign(new MACSigner(SECRET.getBytes(StandardCharsets.UTF_8)));
		return jwt.serialize();
	}

	private static String minimal() {
		return "{\"name\":\"Negocio\",\"category\":\"food\",\"prepType\":\"instant\"}";
	}

	private static org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder createBusiness(Owner o,
			String body) {
		return post("/me/business").header("Authorization", "Bearer " + o.token())
			.contentType(MediaType.APPLICATION_JSON)
			.content(body);
	}

	private static org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder patchBusiness(Owner o,
			String body) {
		return patch("/me/business").header("Authorization", "Bearer " + o.token())
			.contentType(MediaType.APPLICATION_JSON)
			.content(body);
	}

	private String createAndGetId(Owner o, String body) throws Exception {
		var res = mvc.perform(createBusiness(o, body)).andExpect(status().isCreated()).andReturn();
		return json.readTree(res.getResponse().getContentAsString()).get("id").asString();
	}

	private void expectCreateError(Owner o, String body, String message) throws Exception {
		mvc.perform(createBusiness(o, body))
			.andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.error.code").value("VALIDATION_ERROR"))
			.andExpect(jsonPath("$.error.message").value(message));
	}

	private void expectPatchError(Owner o, String body, String message) throws Exception {
		mvc.perform(patchBusiness(o, body))
			.andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.error.code").value("VALIDATION_ERROR"))
			.andExpect(jsonPath("$.error.message").value(message));
	}

	private void assertIds(String url, String idA, String idB, boolean expectA, boolean expectB) throws Exception {
		assertIds(get(url), idA, idB, expectA, expectB);
	}

	private void assertIds(org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder request,
			String idA, String idB, boolean expectA, boolean expectB) throws Exception {
		String url = String.valueOf(request.buildRequest(new org.springframework.mock.web.MockServletContext())
			.getParameterMap()
			.entrySet()
			.stream()
			.map(e -> e.getKey() + "=" + String.join(",", e.getValue()))
			.toList());
		var res = mvc.perform(request).andExpect(status().isOk()).andReturn();
		String body = res.getResponse().getContentAsString();
		assertThat(body.contains(idA)).as(url + " contains A").isEqualTo(expectA);
		assertThat(body.contains(idB)).as(url + " contains B").isEqualTo(expectB);
	}

	private void insertProduct(String id, String businessId, String name, long price, boolean trackStock, int stock,
			Integer prepMinutes, String imageUrl, boolean active) {
		jdbc.update("INSERT INTO products (id, business_id, name, price_cents, track_stock, stock, prep_minutes, "
				+ "image_url, active, created_at) VALUES (?,?,?,?,?,?,?,?,?,1)", id, businessId, name, price,
				trackStock, stock, prepMinutes, imageUrl, active);
	}

	/** A different, valid CLABE: same 17-digit prefix family with the last prefix digit changed. */
	private static String validClabeOtherThan(String clabe) {
		String prefix = clabe.substring(0, 16) + (clabe.charAt(16) == '9' ? '0' : (char) (clabe.charAt(16) + 1));
		for (char check = '0'; check <= '9'; check++) {
			String candidate = prefix + check;
			if (Clabe.isValid(candidate)) {
				return candidate;
			}
		}
		throw new IllegalStateException("no valid check digit");
	}

}
