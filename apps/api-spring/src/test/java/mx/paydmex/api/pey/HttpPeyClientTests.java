package mx.paydmex.api.pey;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;

import com.sun.net.httpserver.HttpServer;

import mx.paydmex.api.common.AppException;
import mx.paydmex.api.config.AppProperties;
import mx.paydmex.api.pey.PeyClient.CodiQr;
import mx.paydmex.api.pey.PeyClient.CodiQrRequest;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

/** Talks to a throwaway local HTTP server standing in for pey. Never the real API. */
class HttpPeyClientTests {

	private final JsonMapper json = JsonMapper.builder().build();

	private HttpServer server;

	private volatile String path;

	private volatile String auth;

	private volatile String body;

	private volatile int replyStatus;

	private volatile String replyBody;

	@BeforeEach
	void start() throws IOException {
		replyStatus = 200;
		replyBody = "{\"id\":\"qr_1\",\"qrString\":\"000201-qr\",\"qrImage\":null}";
		server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
		server.createContext("/", ex -> {
			path = ex.getRequestURI().getPath();
			auth = ex.getRequestHeaders().getFirst("Authorization");
			body = new String(ex.getRequestBody().readAllBytes(), StandardCharsets.UTF_8);
			byte[] out = replyBody.getBytes(StandardCharsets.UTF_8);
			ex.getResponseHeaders().add("Content-Type", "application/json");
			ex.sendResponseHeaders(replyStatus, out.length);
			ex.getResponseBody().write(out);
			ex.close();
		});
		server.start();
	}

	@AfterEach
	void stop() {
		server.stop(0);
	}

	private HttpPeyClient client(String apiKey, String override) {
		String url = "http://127.0.0.1:" + server.getAddress().getPort();
		return new HttpPeyClient(new AppProperties(new AppProperties.Jwt("j".repeat(40)),
				new AppProperties.Pey(url, apiKey, "", override), new AppProperties.Llm("http://llm.invalid", null, null),
				new AppProperties.Cors(List.of()), new AppProperties.DevRoutes(false)));
	}

	private static CodiQrRequest request(String bankAccountId) {
		return new CodiQrRequest(12345, "Pedido ABC123", "1234567", 600, bankAccountId,
				Map.of("orderId", "o1", "businessId", "b1"));
	}

	@Test
	void centavosBecomePesosWithTwoDecimals() {
		assertThat(HttpPeyClient.resolvePesos(12345, null).toPlainString()).isEqualTo("123.45");
		assertThat(HttpPeyClient.resolvePesos(5, null).toPlainString()).isEqualTo("0.05");
		assertThat(HttpPeyClient.resolvePesos(100, "").toPlainString()).isEqualTo("1.00");
		assertThat(HttpPeyClient.resolvePesos(0, null).toPlainString()).isEqualTo("0.00");
	}

	@Test
	void positiveOverrideReplacesTheAmountAndBadOverridesAreIgnored() {
		assertThat(HttpPeyClient.resolvePesos(12345, "0.01").toPlainString()).isEqualTo("0.01");
		assertThat(HttpPeyClient.resolvePesos(12345, " 2.5 ").toPlainString()).isEqualTo("2.50");
		assertThat(HttpPeyClient.resolvePesos(12345, "0.019").toPlainString()).isEqualTo("0.02");
		for (String bad : new String[] { "abc", "-1", "0", "0.001", "1e", "  " }) {
			assertThat(HttpPeyClient.resolvePesos(12345, bad).toPlainString()).as("override '%s'", bad)
				.isEqualTo("123.45");
		}
	}

	@Test
	void createCodiQrSendsTheRealAmountInPesosWhenThereIsNoOverride() throws Exception {
		CodiQr qr = client("key-1", "").createCodiQr(request(null));

		assertThat(qr).isEqualTo(new CodiQr("qr_1", "000201-qr"));
		assertThat(path).isEqualTo("/codi/qr");
		assertThat(auth).isEqualTo("Bearer key-1");
		JsonNode sent = json.readTree(body);
		assertThat(sent.get("amount").decimalValue().toPlainString()).isEqualTo("123.45");
		assertThat(sent.get("concept").asString()).isEqualTo("Pedido ABC123");
		assertThat(sent.get("numRef").asString()).isEqualTo("1234567");
		assertThat(sent.get("expiration").asInt()).isEqualTo(600);
		assertThat(sent.get("generateImage").asBoolean()).isFalse();
		assertThat(sent.at("/metadata/orderId").asString()).isEqualTo("o1");
		assertThat(sent.has("bankAccountId")).isFalse();
	}

	@Test
	void testAmountOverrideIsWhatPeyIsAskedToCharge() throws Exception {
		client("key-1", "0.01").createCodiQr(request("ba_1"));

		JsonNode sent = json.readTree(body);
		assertThat(sent.get("amount").decimalValue().toPlainString()).isEqualTo("0.01");
		assertThat(sent.get("bankAccountId").asString()).isEqualTo("ba_1");
	}

	@Test
	void peyErrorPayloadBecomes502WithTheRequestId() {
		replyStatus = 400;
		replyBody = "{\"error\":{\"message\":\"amount too low\",\"type\":\"invalid\",\"requestId\":\"req_9\"}}";

		assertThatThrownBy(() -> client("key-1", "").createCodiQr(request(null))).isInstanceOfSatisfying(
				AppException.class, ex -> {
					assertThat(ex.status()).isEqualTo(HttpStatus.BAD_GATEWAY);
					assertThat(ex.code()).isEqualTo("PEY_ERROR");
					assertThat(ex.getMessage()).isEqualTo("amount too low [req_9]");
				});
	}

	@Test
	void nonJsonFailureBodyStillBecomes502() {
		replyStatus = 500;
		replyBody = "boom";

		assertThatThrownBy(() -> client("key-1", "").createCodiQr(request(null))).isInstanceOfSatisfying(
				AppException.class, ex -> assertThat(ex.getMessage()).isEqualTo("pey error (HTTP 500)"));
	}

	@Test
	void successWithoutQrStringIsAnInvalidPayload() {
		replyBody = "{\"id\":\"qr_1\"}";

		assertThatThrownBy(() -> client("key-1", "").createCodiQr(request(null))).isInstanceOfSatisfying(
				AppException.class, ex -> {
					assertThat(ex.status()).isEqualTo(HttpStatus.BAD_GATEWAY);
					assertThat(ex.getMessage()).isEqualTo("Invalid response payload from pey");
				});
	}

	@Test
	void missingApiKeyIs503WithoutCallingPey() {
		assertThatThrownBy(() -> client("", "").createCodiQr(request(null))).isInstanceOfSatisfying(AppException.class,
				ex -> {
					assertThat(ex.status()).isEqualTo(HttpStatus.SERVICE_UNAVAILABLE);
					assertThat(ex.code()).isEqualTo("PEY_NOT_CONFIGURED");
				});
		assertThat(path).isNull();
	}

	@Test
	void registerBankAccountStillWorksThroughTheSharedTransport() {
		replyBody = "{\"id\":\"ba_7\",\"codiStatus\":\"PENDING\"}";

		var account = client("key-1", "").registerBankAccount("alias", "Name", "012345678901234567");

		assertThat(account).isEqualTo(new PeyClient.BankAccount("ba_7", "PENDING"));
		assertThat(path).isEqualTo("/bank-account");
	}

}
