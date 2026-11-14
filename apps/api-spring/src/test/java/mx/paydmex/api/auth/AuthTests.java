package mx.paydmex.api.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Date;
import java.util.Map;

import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.MACSigner;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class AuthTests {

	private static final String SECRET = "unit-test-only-hs256-key-0123456789-abcdef";

	/** Generated with the Node API's bcryptjs (cost 10, $2b$): proves hashes created by Node verify here. */
	private static final String NODE_HASH_PLAIN = "$2b$10$hG7XQSiPMaVu1PG6G59eBebLBdknsRbcZUBDv46Tn8v.Njnqu5nmO";

	private static final String NODE_PASSWORD_PLAIN = "s3cret-passw0rd";

	/** bcryptjs, cost 12, non-ASCII password. */
	private static final String NODE_HASH_UNICODE = "$2b$12$UqwjHi5T801jDhqe9iDPqeYtx0TikLlESfLIpSq1UiM./Jw7v6FN.";

	/** NFC spelling of the Node fixture password, built from code points so no editor or encoding can alter it. */
	private static final String NODE_PASSWORD_UNICODE = "contrase" + (char) 0xF1 + "a-" + (char) 0xF1 + "and"
			+ (char) 0xFA + "-9";

	@Autowired
	MockMvc mvc;

	@Autowired
	JdbcTemplate jdbc;

	private final JsonMapper json = JsonMapper.builder().build();

	@AfterEach
	void cleanup() {
		jdbc.update("DELETE FROM businesses WHERE owner_id LIKE 'auth-test-%' OR owner_id IN "
				+ "(SELECT id FROM users WHERE email LIKE '%@auth-test.mx')");
		jdbc.update("DELETE FROM users WHERE id LIKE 'auth-test-%' OR email LIKE '%@auth-test.mx'");
	}

	// register

	@Test
	void registerCreatesUserAndReturnsContractShape() throws Exception {
		long before = Instant.now().getEpochSecond();
		MvcResult res = mvc.perform(register("Ana@Auth-Test.mx", "password-1", "  Ana  "))
			.andExpect(status().isCreated())
			.andExpect(jsonPath("$.user.email").value("ana@auth-test.mx"))
			.andExpect(jsonPath("$.user.name").value("Ana"))
			.andExpect(jsonPath("$.user.id").value(org.hamcrest.Matchers.matchesPattern("[0-9A-HJKMNP-TV-Z]{26}")))
			.andExpect(jsonPath("$.user.passwordHash").doesNotExist())
			.andExpect(jsonPath("$.user.password_hash").doesNotExist())
			.andReturn();
		JsonNode body = json.readTree(res.getResponse().getContentAsString());
		long createdAt = body.at("/user/createdAt").asLong();
		assertThat(createdAt).isBetween(before, Instant.now().getEpochSecond() + 1); // seconds, never ms
		String storedHash = jdbc.queryForObject("SELECT password_hash FROM users WHERE email='ana@auth-test.mx'",
				String.class);
		assertThat(storedHash).startsWith("$2a$10$").doesNotContain("password-1");
	}

	@Test
	void registerTokenHasNodeCompatibleHeaderAndClaims() throws Exception {
		MvcResult res = mvc.perform(register("tok@auth-test.mx", "password-1", "Tok")).andReturn();
		JsonNode body = json.readTree(res.getResponse().getContentAsString());
		SignedJWT jwt = SignedJWT.parse(body.get("token").asString());

		assertThat(jwt.getHeader().getAlgorithm()).isEqualTo(JWSAlgorithm.HS256);
		assertThat(jwt.verify(new com.nimbusds.jose.crypto.MACVerifier(SECRET.getBytes(StandardCharsets.UTF_8))))
			.isTrue();
		JWTClaimsSet claims = jwt.getJWTClaimsSet();
		assertThat(claims.getSubject()).isEqualTo(body.at("/user/id").asString());
		assertThat(claims.getStringClaim("email")).isEqualTo("tok@auth-test.mx");
		long ttl = claims.getExpirationTime().toInstant().getEpochSecond()
				- claims.getIssueTime().toInstant().getEpochSecond();
		assertThat(ttl).isEqualTo(7 * 24 * 3600L);
	}

	@Test
	void registerDuplicateEmailIgnoringCaseIs409() throws Exception {
		mvc.perform(register("dup@auth-test.mx", "password-1", "A")).andExpect(status().isCreated());
		mvc.perform(register("DUP@auth-test.mx", "password-2", "B"))
			.andExpect(status().isConflict())
			.andExpect(jsonPath("$.error.code").value("EMAIL_EXISTS"));
	}

	@Test
	void registerValidationErrors() throws Exception {
		mvc.perform(register("a@auth-test.mx", "short", "A"))
			.andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.error.code").value("VALIDATION_ERROR"))
			.andExpect(jsonPath("$.error.message").value("password: must be at least 8 characters"));
		mvc.perform(register("not-an-email", "password-1", "A"))
			.andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.error.message").value("email: must be a valid email"));
		mvc.perform(register("a@auth-test.mx", "password-1", "   "))
			.andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.error.message").value("name: is required"));
		mvc.perform(post("/auth/register").contentType(MediaType.APPLICATION_JSON).content("{}"))
			.andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.error.code").value("VALIDATION_ERROR"));
	}

	@Test
	void registerRejectsPasswordOverBcrypt72Bytes() throws Exception {
		mvc.perform(register("long@auth-test.mx", "x".repeat(73), "A"))
			.andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.error.code").value("VALIDATION_ERROR"))
			.andExpect(jsonPath("$.error.message").value("password: must be at most 72 bytes"));
	}

	// login

	@Test
	void loginAcceptsPasswordHashedByNodeBcryptjs() throws Exception {
		insertUser("auth-test-node1", "node1@auth-test.mx", NODE_HASH_PLAIN, "Node Uno");
		mvc.perform(login("node1@auth-test.mx", NODE_PASSWORD_PLAIN))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.user.id").value("auth-test-node1"))
			.andExpect(jsonPath("$.token").isNotEmpty());
	}

	@Test
	void loginAcceptsNonAsciiPasswordHashedByNodeBcryptjsCost12() throws Exception {
		insertUser("auth-test-node2", "node2@auth-test.mx", NODE_HASH_UNICODE, "Node Dos");
		mvc.perform(login("node2@auth-test.mx", NODE_PASSWORD_UNICODE)).andExpect(status().isOk());
	}

	@Test
	void loginNormalizesEmailCase() throws Exception {
		insertUser("auth-test-node3", "node3@auth-test.mx", NODE_HASH_PLAIN, "Node Tres");
		mvc.perform(login("NODE3@Auth-Test.MX", NODE_PASSWORD_PLAIN)).andExpect(status().isOk());
	}

	@Test
	void wrongPasswordAndUnknownEmailAreIndistinguishable401() throws Exception {
		insertUser("auth-test-node4", "node4@auth-test.mx", NODE_HASH_PLAIN, "Node Cuatro");
		String wrongPassword = mvc.perform(login("node4@auth-test.mx", "nope-nope-nope"))
			.andExpect(status().isUnauthorized())
			.andExpect(jsonPath("$.error.code").value("INVALID_CREDENTIALS"))
			.andReturn()
			.getResponse()
			.getContentAsString();
		String unknownEmail = mvc.perform(login("ghost@auth-test.mx", "nope-nope-nope"))
			.andExpect(status().isUnauthorized())
			.andReturn()
			.getResponse()
			.getContentAsString();
		assertThat(unknownEmail).isEqualTo(wrongPassword);
	}

	@Test
	void loginWithPasswordOver72BytesIs401NotA500() throws Exception {
		insertUser("auth-test-node5", "node5@auth-test.mx", NODE_HASH_PLAIN, "Node Cinco");
		mvc.perform(login("node5@auth-test.mx", "y".repeat(100)))
			.andExpect(status().isUnauthorized())
			.andExpect(jsonPath("$.error.code").value("INVALID_CREDENTIALS"));
	}

	@Test
	void loginRequiresBothFields() throws Exception {
		mvc.perform(post("/auth/login").contentType(MediaType.APPLICATION_JSON).content("{\"email\":\"a@b.mx\"}"))
			.andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.error.message").value("password: is required"));
	}

	@Test
	void registeredUserCanLogInAgain() throws Exception {
		mvc.perform(register("again@auth-test.mx", "password-1", "Again")).andExpect(status().isCreated());
		mvc.perform(login("again@auth-test.mx", "password-1")).andExpect(status().isOk());
	}

	// /me

	@Test
	void meRequiresToken() throws Exception {
		mvc.perform(get("/me")).andExpect(status().isUnauthorized())
			.andExpect(jsonPath("$.error.code").value("UNAUTHORIZED"));
	}

	@Test
	void meWithIssuedTokenReturnsUserAndNullBusiness() throws Exception {
		String token = tokenOf(mvc.perform(register("me@auth-test.mx", "password-1", "Me")).andReturn());
		mvc.perform(get("/me").header("Authorization", "Bearer " + token))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.user.email").value("me@auth-test.mx"))
			.andExpect(jsonPath("$.user.passwordHash").doesNotExist())
			.andExpect(content().string(org.hamcrest.Matchers.containsString("\"business\":null")));
	}

	@Test
	void meReturnsOwnBusinessInCamelCase() throws Exception {
		insertUser("auth-test-owner", "owner@auth-test.mx", NODE_HASH_PLAIN, "Owner");
		jdbc.update("""
				INSERT INTO businesses (id,owner_id,name,category,prep_type,lat,lng,clabe,created_at)
				VALUES ('auth-test-biz','auth-test-owner','Tacos','food','made_to_order',19.4,-99.1,'012345678901234567',1700000000)""");
		String token = tokenOf(mvc.perform(login("owner@auth-test.mx", NODE_PASSWORD_PLAIN)).andReturn());
		mvc.perform(get("/me").header("Authorization", "Bearer " + token))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.business.id").value("auth-test-biz"))
			.andExpect(jsonPath("$.business.ownerId").value("auth-test-owner"))
			.andExpect(jsonPath("$.business.prepType").value("made_to_order"))
			.andExpect(jsonPath("$.business.active").value(true))
			.andExpect(jsonPath("$.business.lat").value(19.4))
			.andExpect(jsonPath("$.business.description").value(org.hamcrest.Matchers.nullValue()))
			.andExpect(jsonPath("$.business.createdAt").value(1700000000));
	}

	@Test
	void meDoesNotLeakAnotherUsersBusiness() throws Exception {
		insertUser("auth-test-owner2", "owner2@auth-test.mx", NODE_HASH_PLAIN, "Owner2");
		jdbc.update("""
				INSERT INTO businesses (id,owner_id,name,category,prep_type,created_at)
				VALUES ('auth-test-biz2','auth-test-owner2','Otro','food','instant',1)""");
		String token = tokenOf(mvc.perform(register("other@auth-test.mx", "password-1", "Other")).andReturn());
		mvc.perform(get("/me").header("Authorization", "Bearer " + token))
			.andExpect(status().isOk())
			.andExpect(content().string(org.hamcrest.Matchers.containsString("\"business\":null")));
	}

	@Test
	void validTokenForDeletedUserIs401() throws Exception {
		mvc.perform(get("/me").header("Authorization", "Bearer " + nodeStyleToken("auth-test-deleted", "gone@auth-test.mx")))
			.andExpect(status().isUnauthorized())
			.andExpect(jsonPath("$.error.code").value("UNAUTHORIZED"));
	}

	@Test
	void nodeIssuedTokenWorksOnMe() throws Exception {
		insertUser("auth-test-node6", "node6@auth-test.mx", NODE_HASH_PLAIN, "Node Seis");
		mvc.perform(get("/me").header("Authorization", "Bearer " + nodeStyleToken("auth-test-node6", "node6@auth-test.mx")))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.user.id").value("auth-test-node6"));
	}

	@Test
	void requestRecordsDoNotLeakPasswordsInToString() {
		assertThat(new RegisterRequest("a@b.mx", "super-secret-pw", "A").toString()).doesNotContain("super-secret-pw");
		assertThat(new LoginRequest("a@b.mx", "super-secret-pw").toString()).doesNotContain("super-secret-pw");
	}

	// helpers

	private static org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder register(String email,
			String password, String name) {
		return post("/auth/register").contentType(MediaType.APPLICATION_JSON)
			.content(body(Map.of("email", email, "password", password, "name", name)));
	}

	private static org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder login(String email,
			String password) {
		return post("/auth/login").contentType(MediaType.APPLICATION_JSON)
			.content(body(Map.of("email", email, "password", password)));
	}

	private static String body(Map<String, String> fields) {
		return JsonMapper.builder().build().writeValueAsString(fields);
	}

	private String tokenOf(MvcResult res) throws Exception {
		return json.readTree(res.getResponse().getContentAsString()).get("token").asString();
	}

	private void insertUser(String id, String email, String hash, String name) {
		jdbc.update("INSERT INTO users (id,email,password_hash,name,created_at) VALUES (?,?,?,?,?)", id, email, hash,
				name, 1700000000L);
	}

	/** Same shape jose produces in apps/api: HS256, sub, email, iat, exp. */
	private static String nodeStyleToken(String sub, String email) throws Exception {
		var claims = new JWTClaimsSet.Builder().subject(sub)
			.claim("email", email)
			.issueTime(new Date())
			.expirationTime(new Date(System.currentTimeMillis() + 3_600_000))
			.build();
		var jwt = new SignedJWT(new JWSHeader(JWSAlgorithm.HS256), claims);
		jwt.sign(new MACSigner(SECRET.getBytes(StandardCharsets.UTF_8)));
		return jwt.serialize();
	}

}
