package mx.paydmex.api.ai;

import java.net.http.HttpClient;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import mx.paydmex.api.common.AppException;
import mx.paydmex.api.config.AppProperties;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;
import tools.jackson.databind.node.ArrayNode;
import tools.jackson.databind.node.ObjectNode;

/**
 * OpenAI-compatible {@code /chat/completions} over the JDK HTTP client. One retry on 429 (the wait comes from
 * {@code Retry-After} or the "try again in" hint, capped), then 503 LLM_BUSY. Upstream bodies are never returned or
 * logged: the user only sees a generic message.
 */
@Component
class HttpLlmClient implements LlmClient {

	static final String GENERIC_ERROR = "No pudimos contactar al asistente";

	static final String BUSY_ERROR = "El asistente esta ocupado, intenta de nuevo en unos segundos";

	private static final Logger log = LoggerFactory.getLogger(HttpLlmClient.class);

	private static final long MAX_RETRY_MS = 2500;

	private static final long DEFAULT_RETRY_MS = 500;

	private static final Pattern TRY_AGAIN = Pattern.compile("try again in\\s+(\\d+(?:\\.\\d+)?)\\s*(ms|s)",
			Pattern.CASE_INSENSITIVE);

	private record Reply(int status, String retryAfter, String body) {
	}

	private final JsonMapper json = JsonMapper.builder().build();

	private final RestClient http;

	private final String apiKey;

	private final String model;

	HttpLlmClient(AppProperties props) {
		var factory = new JdkClientHttpRequestFactory(
				HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build());
		factory.setReadTimeout(Duration.ofSeconds(20));
		this.apiKey = props.llm().apiKey() == null ? "" : props.llm().apiKey().trim();
		this.model = props.llm().model() == null ? "" : props.llm().model().trim();
		this.http = RestClient.builder()
			.baseUrl(props.llm().baseUrl().replaceAll("/+$", ""))
			.requestFactory(factory)
			.build();
	}

	@Override
	public LlmResponse chat(List<LlmMessage> messages, List<LlmTool> tools) {
		if (apiKey.isEmpty() || model.isEmpty()) {
			throw new AppException(HttpStatus.SERVICE_UNAVAILABLE, "AI_NOT_CONFIGURED",
					"El asistente no esta configurado");
		}
		String payload = json.writeValueAsString(requestBody(messages, tools));

		Reply reply = send(payload);
		if (reply.status() == 429) {
			sleep(retryDelayMs(reply));
			reply = send(payload);
			if (reply.status() == 429) {
				throw new AppException(HttpStatus.SERVICE_UNAVAILABLE, "LLM_BUSY", BUSY_ERROR);
			}
		}
		if (reply.status() < 200 || reply.status() >= 300) {
			throw upstreamError("HTTP " + reply.status());
		}
		return parse(reply);
	}

	private ObjectNode requestBody(List<LlmMessage> messages, List<LlmTool> tools) {
		ObjectNode body = json.createObjectNode();
		body.put("model", model);
		ArrayNode msgs = body.putArray("messages");
		for (LlmMessage m : messages) {
			msgs.add(messageNode(m));
		}
		if (!tools.isEmpty()) {
			ArrayNode defs = body.putArray("tools");
			for (LlmTool t : tools) {
				ObjectNode fn = json.createObjectNode();
				fn.put("name", t.name());
				fn.put("description", t.description());
				fn.set("parameters", json.valueToTree(t.parameters()));
				ObjectNode def = defs.addObject();
				def.put("type", "function");
				def.set("function", fn);
			}
			body.put("tool_choice", "auto");
		}
		body.put("temperature", 0.2);
		body.put("max_completion_tokens", 400);
		return body;
	}

	private ObjectNode messageNode(LlmMessage m) {
		ObjectNode node = json.createObjectNode();
		switch (m) {
			case LlmMessage.System s -> node.put("role", "system").put("content", s.content());
			case LlmMessage.User u -> node.put("role", "user").put("content", u.content());
			case LlmMessage.Tool t -> {
				node.put("role", "tool").put("tool_call_id", t.toolCallId());
				if (t.name() != null) {
					node.put("name", t.name());
				}
				node.put("content", t.content());
			}
			case LlmMessage.Assistant a -> {
				node.put("role", "assistant");
				if (a.content() == null) {
					node.putNull("content");
				}
				else {
					node.put("content", a.content());
				}
				if (a.toolCalls() != null && !a.toolCalls().isEmpty()) {
					ArrayNode calls = node.putArray("tool_calls");
					for (LlmToolCall c : a.toolCalls()) {
						ObjectNode call = calls.addObject();
						call.put("id", c.id());
						call.put("type", "function");
						call.putObject("function").put("name", c.name()).put("arguments", c.arguments());
					}
				}
			}
		}
		return node;
	}

	private Reply send(String payload) {
		try {
			return http.post()
				.uri("/chat/completions")
				.header(HttpHeaders.AUTHORIZATION, "Bearer " + apiKey)
				.contentType(MediaType.APPLICATION_JSON)
				.body(payload)
				.exchange((req, res) -> new Reply(res.getStatusCode().value(), res.getHeaders().getFirst("Retry-After"),
						readBody(res)));
		}
		catch (RestClientException ex) {
			throw upstreamError("network");
		}
	}

	private static String readBody(RestClient.RequestHeadersSpec.ConvertibleClientHttpResponse res) {
		try {
			return res.bodyTo(String.class);
		}
		catch (RuntimeException ex) {
			return null;
		}
	}

	private LlmResponse parse(Reply reply) {
		JsonNode root;
		try {
			root = json.readTree(reply.body());
		}
		catch (JacksonException | IllegalArgumentException ex) {
			throw upstreamError("HTTP " + reply.status());
		}
		JsonNode choices = root == null ? null : root.get("choices");
		JsonNode msg = choices != null && choices.isArray() && !choices.isEmpty() ? choices.get(0).get("message") : null;
		if (msg == null || !msg.isObject()) {
			throw upstreamError("HTTP " + reply.status());
		}
		String content = msg.hasNonNull("content") && msg.get("content").isString() ? msg.get("content").asString()
				: null;
		var calls = new ArrayList<LlmToolCall>();
		JsonNode rawCalls = msg.get("tool_calls");
		if (rawCalls != null && rawCalls.isArray()) {
			for (int i = 0; i < rawCalls.size(); i++) {
				JsonNode call = rawCalls.get(i);
				JsonNode fn = call.get("function");
				String id = call.hasNonNull("id") && call.get("id").isString() && !call.get("id").asString().isEmpty()
						? call.get("id").asString() : "call_" + (i + 1);
				String name = fn != null && fn.hasNonNull("name") && fn.get("name").isString()
						? fn.get("name").asString() : "";
				JsonNode args = fn == null ? null : fn.get("arguments");
				String arguments = args == null || args.isNull() ? "{}"
						: args.isString() ? args.asString() : json.writeValueAsString(args);
				calls.add(new LlmToolCall(id, name, arguments));
			}
		}
		return new LlmResponse(content, List.copyOf(calls));
	}

	/** Retry-After (seconds) wins, then the provider's "try again in 20ms" hint; always capped. */
	static long retryDelayMs(String retryAfter, String body) {
		if (retryAfter != null) {
			try {
				double seconds = Double.parseDouble(retryAfter.trim());
				if (seconds >= 0) {
					return Math.min(Math.round(seconds * 1000), MAX_RETRY_MS);
				}
			}
			catch (NumberFormatException ex) {
				// HTTP-date form or garbage: fall through to the body hint / default
			}
		}
		if (body != null) {
			Matcher m = TRY_AGAIN.matcher(body);
			if (m.find()) {
				double value = Double.parseDouble(m.group(1));
				double ms = "s".equalsIgnoreCase(m.group(2)) ? value * 1000 : value;
				return Math.min(Math.round(ms), MAX_RETRY_MS);
			}
		}
		return DEFAULT_RETRY_MS;
	}

	private static long retryDelayMs(Reply reply) {
		return retryDelayMs(reply.retryAfter(), reply.body());
	}

	private static void sleep(long ms) {
		try {
			Thread.sleep(ms);
		}
		catch (InterruptedException ex) {
			Thread.currentThread().interrupt();
			throw upstreamError("interrupted");
		}
	}

	private static AppException upstreamError(String what) {
		log.error("LLM upstream error: {}", what);
		return new AppException(HttpStatus.BAD_GATEWAY, "LLM_ERROR", GENERIC_ERROR);
	}

}
