package mx.paydmex.api.pey;

import java.net.http.HttpClient;
import java.time.Duration;
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

	HttpPeyClient(AppProperties props) {
		var factory = new JdkClientHttpRequestFactory(
				HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build());
		factory.setReadTimeout(Duration.ofSeconds(20));
		this.apiKey = props.pey().apiKey() == null ? "" : props.pey().apiKey().trim();
		this.http = RestClient.builder()
			.baseUrl(props.pey().baseUrl().replaceAll("/+$", ""))
			.requestFactory(factory)
			.build();
	}

	@Override
	public BankAccount registerBankAccount(String alias, String name, String clabe) {
		if (apiKey.isEmpty()) {
			throw new AppException(HttpStatus.SERVICE_UNAVAILABLE, "PEY_NOT_CONFIGURED",
					"pey API key is not configured");
		}
		Map<String, String> payload = Map.of("alias", alias, "name", name, "clabe", clabe, "entity", "BUSINESS");
		Reply reply;
		try {
			reply = http.post()
				.uri("/bank-account")
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
		if (body == null || !body.hasNonNull("id") || !body.get("id").isString()) {
			throw new AppException(HttpStatus.BAD_GATEWAY, "PEY_ERROR", "Invalid response payload from pey");
		}
		String codiStatus = body.hasNonNull("codiStatus") ? body.get("codiStatus").asString() : "PENDING";
		return new BankAccount(body.get("id").asString(), codiStatus);
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
