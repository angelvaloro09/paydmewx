package mx.paydmex.api.order;

import java.util.Map;

import mx.paydmex.api.common.AppException;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestController;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;
import tools.jackson.databind.node.ObjectNode;

/**
 * pey callbacks. Public route (no JWT): the Standard Webhooks signature is the authentication. The body is taken as
 * raw bytes because the signature covers the exact bytes pey sent; JSON is parsed only AFTER it verifies.
 */
@RestController
class PeyWebhookController {

	private final StandardWebhookVerifier verifier;

	private final PeyWebhookService service;

	private final JsonMapper json;

	PeyWebhookController(StandardWebhookVerifier verifier, PeyWebhookService service, JsonMapper json) {
		this.verifier = verifier;
		this.service = service;
		this.json = json;
	}

	@PostMapping("/webhooks/pey")
	Map<String, Object> receive(@RequestHeader(name = "webhook-id", required = false) String webhookId,
			@RequestHeader(name = "webhook-timestamp", required = false) String timestamp,
			@RequestHeader(name = "webhook-signature", required = false) String signature,
			@RequestBody(required = false) byte[] rawBody) {
		String id = verifier.verify(webhookId, timestamp, signature, rawBody);
		PeyWebhookService.Result result = service.process(id, parseObject(rawBody));
		return result.duplicate() ? Map.of("ok", true, "duplicate", true) : Map.of("ok", true);
	}

	private ObjectNode parseObject(byte[] rawBody) {
		try {
			JsonNode node = json.readTree(rawBody);
			if (node instanceof ObjectNode object) {
				return object;
			}
		}
		catch (RuntimeException ex) {
			// falls through to the 400 below; the parser message may echo the payload, so it is not forwarded
		}
		throw new AppException(HttpStatus.BAD_REQUEST, "BAD_REQUEST", "Invalid JSON webhook body");
	}

}
