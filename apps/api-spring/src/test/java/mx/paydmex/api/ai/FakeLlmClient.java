package mx.paydmex.api.ai;

import java.util.ArrayDeque;
import java.util.List;
import java.util.Queue;
import java.util.concurrent.CopyOnWriteArrayList;

import mx.paydmex.api.common.AppException;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;

/**
 * Scripted test double: answers queued responses in order (then {@link #fallback}), records every round. Import
 * {@link Config} to replace HttpLlmClient. Never touches the network.
 */
public class FakeLlmClient implements LlmClient {

	public record Call(List<LlmMessage> messages, List<LlmTool> tools) {
	}

	public final List<Call> calls = new CopyOnWriteArrayList<>();

	private final Queue<LlmResponse> script = new ArrayDeque<>();

	/** Used when the script is empty; null = fail loudly so a test cannot silently over-call the model. */
	public volatile LlmResponse fallback;

	/** When set, every call throws it. */
	public volatile AppException failure;

	public synchronized FakeLlmClient say(String content) {
		script.add(new LlmResponse(content, List.of()));
		return this;
	}

	public synchronized FakeLlmClient callTool(String id, String name, String arguments) {
		script.add(new LlmResponse(null, List.of(new LlmToolCall(id, name, arguments))));
		return this;
	}

	/** Text AND a tool call in the same response (models often narrate while calling). */
	public synchronized FakeLlmClient script(String content, String id, String name, String arguments) {
		script.add(new LlmResponse(content, List.of(new LlmToolCall(id, name, arguments))));
		return this;
	}

	@Override
	public synchronized LlmResponse chat(List<LlmMessage> messages, List<LlmTool> tools) {
		calls.add(new Call(messages, tools));
		if (failure != null) {
			throw failure;
		}
		LlmResponse next = script.poll();
		if (next != null) {
			return next;
		}
		if (fallback != null) {
			return fallback;
		}
		throw new AssertionError("FakeLlmClient: no scripted response for round " + calls.size());
	}

	/** Text of the {@code index}-th tool message the model saw in round {@code round} (0-based). */
	public String toolOutput(int round, int index) {
		return calls.get(round)
			.messages()
			.stream()
			.filter(LlmMessage.Tool.class::isInstance)
			.map(m -> ((LlmMessage.Tool) m).content())
			.toList()
			.get(index);
	}

	public synchronized void reset() {
		calls.clear();
		script.clear();
		fallback = null;
		failure = null;
	}

	@TestConfiguration
	public static class Config {

		@Bean
		@Primary
		FakeLlmClient fakeLlmClient() {
			return new FakeLlmClient();
		}

	}

}
