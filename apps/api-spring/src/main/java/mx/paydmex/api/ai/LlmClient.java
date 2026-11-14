package mx.paydmex.api.ai;

import java.util.List;
import java.util.Map;

/** Outbound OpenAI-compatible chat API. Interface so tests inject a fake and never touch the network. */
public interface LlmClient {

	/**
	 * One {@code POST /chat/completions} round with tool calling. Throws AppException 503 AI_NOT_CONFIGURED /
	 * 503 LLM_BUSY / 502 LLM_ERROR; upstream bodies are never exposed to the caller.
	 */
	LlmResponse chat(List<LlmMessage> messages, List<LlmTool> tools);

	sealed interface LlmMessage {

		record System(String content) implements LlmMessage {
		}

		record User(String content) implements LlmMessage {
		}

		/** {@code content} may be null when the model only asked for tools. */
		record Assistant(String content, List<LlmToolCall> toolCalls) implements LlmMessage {
		}

		record Tool(String toolCallId, String name, String content) implements LlmMessage {
		}

	}

	/** {@code parameters} is a JSON Schema object. */
	record LlmTool(String name, String description, Map<String, Object> parameters) {
	}

	/** {@code arguments} is the raw JSON string the model produced (it may be malformed). */
	record LlmToolCall(String id, String name, String arguments) {
	}

	record LlmResponse(String content, List<LlmToolCall> toolCalls) {
	}

}
