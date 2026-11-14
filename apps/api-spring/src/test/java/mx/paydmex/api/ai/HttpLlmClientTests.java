package mx.paydmex.api.ai;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CopyOnWriteArrayList;

import com.sun.net.httpserver.HttpServer;

import mx.paydmex.api.ai.LlmClient.LlmMessage;
import mx.paydmex.api.ai.LlmClient.LlmResponse;
import mx.paydmex.api.ai.LlmClient.LlmTool;
import mx.paydmex.api.ai.LlmClient.LlmToolCall;
import mx.paydmex.api.common.AppException;
import mx.paydmex.api.config.AppProperties;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

/** Talks to a throwaway local HTTP server standing in for the LLM provider. Never the real API. */
class HttpLlmClientTests {

	private static final String OK = "{\"choices\":[{\"message\":{\"content\":\"Hola\",\"tool_calls\":[]}}]}";

	private final JsonMapper json = JsonMapper.builder().build();

	private HttpServer server;

	private final List<String> bodies = new CopyOnWriteArrayList<>();

	private final List<String> auths = new CopyOnWriteArrayList<>();

	/** One scripted reply per request; the last one repeats. Entry = status, body, optional Retry-After. */
	private final List<String[]> replies = new ArrayList<>();

	@BeforeEach
	void start() throws IOException {
		server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
		server.createContext("/", ex -> {
			bodies.add(new String(ex.getRequestBody().readAllBytes(), StandardCharsets.UTF_8));
			auths.add(ex.getRequestHeaders().getFirst("Authorization"));
			String[] reply = replies.get(Math.min(bodies.size() - 1, replies.size() - 1));
			byte[] out = reply[1].getBytes(StandardCharsets.UTF_8);
			ex.getResponseHeaders().add("Content-Type", "application/json");
			if (reply.length > 2) {
				ex.getResponseHeaders().add("Retry-After", reply[2]);
			}
			ex.sendResponseHeaders(Integer.parseInt(reply[0]), out.length);
			ex.getResponseBody().write(out);
			ex.close();
		});
		server.start();
	}

	@AfterEach
	void stop() {
		server.stop(0);
	}

	private HttpLlmClient client(String apiKey, String model) {
		String url = "http://127.0.0.1:" + server.getAddress().getPort() + "/v1/";
		return new HttpLlmClient(new AppProperties(new AppProperties.Jwt("j".repeat(40)),
				new AppProperties.Pey("http://pey.invalid", null, null, null), new AppProperties.Llm(url, apiKey, model),
				new AppProperties.Cors(List.of()), new AppProperties.DevRoutes(false)));
	}

	private HttpLlmClient client() {
		return client("llm-key", "fake-model");
	}

	private static List<LlmMessage> hello() {
		return List.of(new LlmMessage.User("Hola"));
	}

	@Test
	void sendsAnOpenAiCompatibleRequestWithBearerAuthAndTools() throws Exception {
		replies.add(new String[] { "200", OK });
		var tool = new LlmTool("list_products", "Lista productos", Map.of("type", "object", "properties", Map.of()));
		List<LlmMessage> messages = List.of(new LlmMessage.System("sys"), new LlmMessage.User("hola"),
				new LlmMessage.Assistant(null, List.of(new LlmToolCall("call_1", "list_products", "{}"))),
				new LlmMessage.Tool("call_1", "list_products", "{\"products\":[]}"));

		LlmResponse res = client().chat(messages, List.of(tool));

		assertThat(res.content()).isEqualTo("Hola");
		assertThat(res.toolCalls()).isEmpty();
		assertThat(auths).containsExactly("Bearer llm-key");
		JsonNode sent = json.readTree(bodies.getFirst());
		assertThat(sent.get("model").asString()).isEqualTo("fake-model");
		assertThat(sent.get("tool_choice").asString()).isEqualTo("auto");
		assertThat(sent.get("temperature").asDouble()).isEqualTo(0.2);
		assertThat(sent.get("max_completion_tokens").asInt()).isEqualTo(400);
		assertThat(sent.at("/tools/0/type").asString()).isEqualTo("function");
		assertThat(sent.at("/tools/0/function/name").asString()).isEqualTo("list_products");
		assertThat(sent.at("/tools/0/function/parameters/type").asString()).isEqualTo("object");
		assertThat(sent.at("/messages/0/role").asString()).isEqualTo("system");
		assertThat(sent.at("/messages/2/role").asString()).isEqualTo("assistant");
		assertThat(sent.at("/messages/2/content").isNull()).isTrue();
		assertThat(sent.at("/messages/2/tool_calls/0/id").asString()).isEqualTo("call_1");
		assertThat(sent.at("/messages/2/tool_calls/0/function/arguments").asString()).isEqualTo("{}");
		assertThat(sent.at("/messages/3/role").asString()).isEqualTo("tool");
		assertThat(sent.at("/messages/3/tool_call_id").asString()).isEqualTo("call_1");
	}

	@Test
	void omitsToolsWhenThereAreNone() throws Exception {
		replies.add(new String[] { "200", OK });
		client().chat(hello(), List.of());
		JsonNode sent = json.readTree(bodies.getFirst());
		assertThat(sent.has("tools")).isFalse();
		assertThat(sent.has("tool_choice")).isFalse();
	}

	@Test
	void parsesToolCallsWithStringOrObjectArgumentsAndFillsMissingIds() {
		replies.add(new String[] { "200", "{\"choices\":[{\"message\":{\"content\":null,\"tool_calls\":["
				+ "{\"id\":\"a1\",\"function\":{\"name\":\"record_sale\",\"arguments\":\"{\\\"x\\\":1}\"}},"
				+ "{\"function\":{\"name\":\"list_products\",\"arguments\":{\"query\":\"taco\"}}}]}}]}" });

		LlmResponse res = client().chat(hello(), List.of());

		assertThat(res.content()).isNull();
		assertThat(res.toolCalls()).containsExactly(new LlmToolCall("a1", "record_sale", "{\"x\":1}"),
				new LlmToolCall("call_2", "list_products", "{\"query\":\"taco\"}"));
	}

	@Test
	void notConfiguredWithoutKeyOrModelAndNeverCallsOut() {
		assertThatThrownBy(() -> client("", "m").chat(hello(), List.of())).isInstanceOfSatisfying(AppException.class,
				e -> {
					assertThat(e.status()).isEqualTo(HttpStatus.SERVICE_UNAVAILABLE);
					assertThat(e.code()).isEqualTo("AI_NOT_CONFIGURED");
				});
		assertThatThrownBy(() -> client("k", "  ").chat(hello(), List.of())).isInstanceOfSatisfying(AppException.class,
				e -> assertThat(e.code()).isEqualTo("AI_NOT_CONFIGURED"));
		assertThat(bodies).isEmpty();
	}

	@Test
	void retriesOnceOn429ThenSucceeds() {
		replies.add(new String[] { "429", "{\"error\":{\"message\":\"Rate limit reached, try again in 10ms\"}}" });
		replies.add(new String[] { "200", "{\"choices\":[{\"message\":{\"content\":\"Hola tras reintento\"}}]}" });

		LlmResponse res = client().chat(hello(), List.of());

		assertThat(res.content()).isEqualTo("Hola tras reintento");
		assertThat(bodies).hasSize(2);
	}

	@Test
	void secondConsecutive429IsBusy() {
		replies.add(new String[] { "429", "{\"error\":{\"message\":\"slow down\"}}", "0.005" });

		assertThatThrownBy(() -> client().chat(hello(), List.of())).isInstanceOfSatisfying(AppException.class, e -> {
			assertThat(e.status()).isEqualTo(HttpStatus.SERVICE_UNAVAILABLE);
			assertThat(e.code()).isEqualTo("LLM_BUSY");
			assertThat(e.getMessage()).isEqualTo(HttpLlmClient.BUSY_ERROR);
		});
		assertThat(bodies).hasSize(2);
	}

	@Test
	void upstreamErrorIsGenericAndNeverLeaksTheProviderBody() {
		replies.add(new String[] { "500", "{\"error\":{\"message\":\"Internal error for org_secret_999999\"}}" });

		assertThatThrownBy(() -> client().chat(hello(), List.of())).isInstanceOfSatisfying(AppException.class, e -> {
			assertThat(e.status()).isEqualTo(HttpStatus.BAD_GATEWAY);
			assertThat(e.code()).isEqualTo("LLM_ERROR");
			assertThat(e.getMessage()).isEqualTo(HttpLlmClient.GENERIC_ERROR).doesNotContain("org_secret");
		});
		assertThat(bodies).hasSize(1);
	}

	@Test
	void malformedOrEmptySuccessBodiesAreUpstreamErrors() {
		for (String body : List.of("not json", "{}", "{\"choices\":[]}", "{\"choices\":[{}]}", "")) {
			replies.clear();
			bodies.clear();
			replies.add(new String[] { "200", body });
			assertThatThrownBy(() -> client().chat(hello(), List.of())).as(body)
				.isInstanceOfSatisfying(AppException.class, e -> assertThat(e.code()).isEqualTo("LLM_ERROR"));
		}
	}

	@Test
	void unreachableProviderIsAnUpstreamError() {
		server.stop(0);
		assertThatThrownBy(() -> client().chat(hello(), List.of())).isInstanceOfSatisfying(AppException.class,
				e -> assertThat(e.code()).isEqualTo("LLM_ERROR"));
	}

	@Test
	void retryDelayPrefersRetryAfterThenTheBodyHintAndIsCapped() {
		assertThat(HttpLlmClient.retryDelayMs("2", "try again in 10ms")).isEqualTo(2000);
		assertThat(HttpLlmClient.retryDelayMs("60", null)).isEqualTo(2500);
		assertThat(HttpLlmClient.retryDelayMs(null, "Please try again in 20ms.")).isEqualTo(20);
		assertThat(HttpLlmClient.retryDelayMs(null, "try again in 1.5s")).isEqualTo(1500);
		assertThat(HttpLlmClient.retryDelayMs(null, "try again in 90s")).isEqualTo(2500);
		assertThat(HttpLlmClient.retryDelayMs("Wed, 21 Oct 2026 07:28:00 GMT", null)).isEqualTo(500);
		assertThat(HttpLlmClient.retryDelayMs(null, null)).isEqualTo(500);
	}

}
