package mx.paydmex.api.pey;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.net.http.HttpClient;
import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.Map;

import mx.paydmex.api.common.AppException;
import mx.paydmex.api.config.AppProperties;

import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import tools.jackson.databind.JsonNode;

@Component
class HttpPeyClient implements PeyClient {

	private record Reply(int status, JsonNode body) {
	}

	private final RestClient http;

	private final String apiKey;

	private final String testAmountOverride;

	HttpPeyClient(AppProperties props) {
		var factory = new JdkClientHttpRequestFactory(
				HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build());
		factory.setReadTimeout(Duration.ofSeconds(20));
		this.apiKey = props.pey().apiKey() == null ? "" : props.pey().apiKey().trim();
		this.testAmountOverride = props.pey().testAmountOverride();
		this.http = RestClient.builder()
			.baseUrl(props.pey().baseUrl().replaceAll("/+$", ""))
			.requestFactory(factory)
			.build();
	}

	@Override
	public BankAccount registerBankAccount(String alias, String name, String clabe) {
		JsonNode body = post("/bank-account",
				Map.of("alias", alias, "name", name, "clabe", clabe, "entity", "BUSINESS"));
		String id = text(body, "id");
		if (id == null) {
			throw invalidPayload();
		}
		String codiStatus = text(body, "codiStatus");
		return new BankAccount(id, codiStatus == null ? "PENDING" : codiStatus);
	}

	@Override
	public CodiQr createCodiQr(CodiQrRequest req) {
		var payload = new LinkedHashMap<String, Object>();
		payload.put("amount", resolvePesos(req.amountCents(), testAmountOverride));
		payload.put("concept", req.concept());
		payload.put("expiration", req.expirationSec());
		payload.put("numRef", req.numRef());
		payload.put("generateImage", false);
		payload.put("metadata", req.metadata() == null ? Map.of() : req.metadata());
		if (req.bankAccountId() != null) {
			payload.put("bankAccountId", req.bankAccountId());
		}
		JsonNode body = post("/codi/qr", payload);
		String id = text(body, "id");
		String qrString = text(body, "qrString");
		if (id == null || qrString == null) {
			throw invalidPayload();
		}
		return new CodiQr(id, qrString);
	}

	/**
	 * The only place centavos become pesos. A positive {@code PEY_TEST_AMOUNT_OVERRIDE} (rounded to 2 decimals, still
	 * >= 0.01) replaces the real amount so production tests charge a few cents; blank/invalid/non-positive = real amount.
	 */
	static BigDecimal resolvePesos(long amountCents, String overrideRaw) {
		if (overrideRaw != null && !overrideRaw.isBlank()) {
			try {
				BigDecimal override = new BigDecimal(overrideRaw.trim()).setScale(2, RoundingMode.HALF_UP);
				if (override.signum() > 0) {
					return override;
				}
			}
			catch (NumberFormatException ex) {
				// not a number: fall through to the real amount, like the Node API
			}
		}
		return BigDecimal.valueOf(amountCents, 2);
	}

	/** Shared transport: auth, error mapping (pey {@code {error:{message,requestId}}} -> 502 PEY_ERROR), body. */
	private JsonNode post(String path, Object payload) {
		if (apiKey.isEmpty()) {
			throw new AppException(HttpStatus.SERVICE_UNAVAILABLE, "PEY_NOT_CONFIGURED",
					"pey API key is not configured");
		}
		Reply reply;
		try {
			reply = http.post()
				.uri(path)
				.header(HttpHeaders.AUTHORIZATION, "Bearer " + apiKey)
				.contentType(MediaType.APPLICATION_JSON)
				.body(payload)
				.exchange((req, res) -> new Reply(res.getStatusCode().value(), parse(res)));
		}
		catch (RestClientException ex) {
			throw new AppException(HttpStatus.BAD_GATEWAY, "PEY_ERROR", "pey request failed");
		}

		JsonNode body = reply.body();
		JsonNode error = body == null ? null : body.get("error");
		if (reply.status() < 200 || reply.status() >= 300 || (error != null && !error.isNull())) {
			String message = "pey error (HTTP " + reply.status() + ")";
			if (error != null && error.hasNonNull("message")) {
				message = error.get("message").asString();
				if (error.hasNonNull("requestId")) {
					message += " [" + error.get("requestId").asString() + "]";
				}
			}
			throw new AppException(HttpStatus.BAD_GATEWAY, "PEY_ERROR", message);
		}
		return body;
	}

	private static String text(JsonNode body, String field) {
		return body != null && body.hasNonNull(field) && body.get(field).isString() ? body.get(field).asString()
				: null;
	}

	private static AppException invalidPayload() {
		return new AppException(HttpStatus.BAD_GATEWAY, "PEY_ERROR", "Invalid response payload from pey");
	}

	/** pey may answer with an empty or non-JSON body on failures; that is handled as "no body". */
	private static JsonNode parse(RestClient.RequestHeadersSpec.ConvertibleClientHttpResponse res) {
		try {
			return res.bodyTo(JsonNode.class);
		}
		catch (RuntimeException ex) {
			return null;
		}
	}

}
