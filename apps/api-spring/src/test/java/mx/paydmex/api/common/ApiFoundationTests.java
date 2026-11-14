package mx.paydmex.api.common;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.options;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.nio.charset.StandardCharsets;
import java.sql.SQLException;
import java.util.Date;

import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.MACSigner;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;

import mx.paydmex.api.config.AppProperties;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class ApiFoundationTests {

	private static final String SECRET = "unit-test-only-hs256-key-0123456789-abcdef";

	@Autowired
	MockMvc mvc;

	@Autowired
	JdbcTemplate jdbc;

	@Test
	void healthIsPublic() throws Exception {
		mvc.perform(get("/health")).andExpect(status().isOk()).andExpect(jsonPath("$.ok").value(true));
	}

	@Test
	void protectedRouteWithoutTokenIs401InErrorShape() throws Exception {
		mvc.perform(get("/orders/x"))
			.andExpect(status().isUnauthorized())
			.andExpect(jsonPath("$.error.code").value("UNAUTHORIZED"))
			.andExpect(jsonPath("$.error.message").value("Unauthorized"));
	}

	@Test
	void unknownRouteIs404WhenAuthenticated() throws Exception {
		mvc.perform(get("/nope").with(jwt()))
			.andExpect(status().isNotFound())
			.andExpect(jsonPath("$.error.code").value("NOT_FOUND"));
	}

	@Test
	void bodyValidationReturnsFirstErrorAsFieldColonMessage() throws Exception {
		mvc.perform(post("/_probe/validate").with(jwt())
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"name\":\"ok\",\"qty\":0}"))
			.andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.error.code").value("VALIDATION_ERROR"))
			.andExpect(jsonPath("$.error.message").value("qty: must be greater than or equal to 1"));
	}

	@Test
	void malformedJsonIs400BadRequest() throws Exception {
		mvc.perform(post("/_probe/validate").with(jwt()).contentType(MediaType.APPLICATION_JSON).content("{nope"))
			.andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.error.code").value("BAD_REQUEST"));
	}

	@Test
	void appExceptionRendersStatusCodeMessage() throws Exception {
		mvc.perform(get("/_probe/app").with(jwt()))
			.andExpect(status().isConflict())
			.andExpect(jsonPath("$.error.code").value("EMAIL_EXISTS"))
			.andExpect(jsonPath("$.error.message").value("Email already registered"));
	}

	@Test
	void unexpectedErrorIsGenericAndLeaksNothing() throws Exception {
		mvc.perform(get("/_probe/boom").with(jwt()))
			.andExpect(status().isInternalServerError())
			.andExpect(jsonPath("$.error.code").value("INTERNAL_ERROR"))
			.andExpect(content().string(org.hamcrest.Matchers.not(org.hamcrest.Matchers.containsString("secret"))));
	}

	@Test
	void validHs256TokenFromNodeStyleClaimsIsAccepted() throws Exception {
		mvc.perform(get("/_probe/me").header("Authorization", "Bearer " + token(SECRET)))
			.andExpect(status().isOk())
			.andExpect(content().string("user-1|a@b.mx"));
	}

	@Test
	void tokenSignedWithOtherKeyIs401() throws Exception {
		mvc.perform(get("/_probe/me").header("Authorization", "Bearer " + token("another-key-another-key-another-key-xx")))
			.andExpect(status().isUnauthorized())
			.andExpect(jsonPath("$.error.code").value("UNAUTHORIZED"));
	}

	@Test
	void corsAllowsListedOriginOnly() throws Exception {
		mvc.perform(options("/health").header("Origin", "http://localhost:3000")
				.header("Access-Control-Request-Method", "GET"))
			.andExpect(status().isOk())
			.andExpect(header().string("Access-Control-Allow-Origin", "http://localhost:3000"));
		mvc.perform(options("/health").header("Origin", "https://evil.example")
				.header("Access-Control-Request-Method", "GET"))
			.andExpect(status().isForbidden());
	}

	@Test
	void flywayCreatedAllTables() {
		Integer n = jdbc.queryForObject("""
				SELECT COUNT(*) FROM information_schema.tables
				WHERE table_schema = 'public' AND table_name IN
				('users','businesses','products','stock_movements','orders','order_items','payments','webhook_events')
				""", Integer.class);
		assertThat(n).isEqualTo(8);
	}

	@Test
	void checkConstraintsRejectBadData() {
		jdbc.update("INSERT INTO users (id,email,password_hash,name,created_at) VALUES ('u1','x@y.mx','h','n',1)");
		jdbc.update("""
				INSERT INTO businesses (id,owner_id,name,category,prep_type,created_at)
				VALUES ('b1','u1','biz','food','instant',1)""");
		assertThatThrownBy(() -> jdbc.update("""
				INSERT INTO orders (id,business_id,status,total_cents,created_at)
				VALUES ('o1','b1','bogus',100,1)""")).hasRootCauseInstanceOf(SQLException.class);
		assertThatThrownBy(() -> jdbc.update("""
				INSERT INTO products (id,business_id,name,price_cents,stock,created_at)
				VALUES ('p1','b1','n',100,-1,1)""")).hasRootCauseInstanceOf(SQLException.class);
	}

	@Test
	void jwtSecretMustBeStrong() {
		assertThatThrownBy(() -> new AppProperties.Jwt("short")).isInstanceOf(IllegalArgumentException.class);
		assertThatThrownBy(() -> new AppProperties.Jwt("change-me")).isInstanceOf(IllegalArgumentException.class);
		assertThatThrownBy(() -> new AppProperties.Jwt(null)).isInstanceOf(IllegalArgumentException.class);
	}

	@Test
	void corsWildcardIsRejected() {
		assertThatThrownBy(() -> new AppProperties.Cors(java.util.List.of("*")))
			.isInstanceOf(IllegalArgumentException.class);
	}

	private static String token(String secret) throws Exception {
		var claims = new JWTClaimsSet.Builder().subject("user-1")
			.claim("email", "a@b.mx")
			.issueTime(new Date())
			.expirationTime(new Date(System.currentTimeMillis() + 3_600_000))
			.build();
		var jwt = new SignedJWT(new JWSHeader(JWSAlgorithm.HS256), claims);
		jwt.sign(new MACSigner(secret.getBytes(StandardCharsets.UTF_8)));
		return jwt.serialize();
	}

}
