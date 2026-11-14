package mx.paydmex.api.ai;

import java.util.ArrayList;
import java.util.List;

import mx.paydmex.api.common.AppException;

import org.springframework.http.HttpStatus;
import tools.jackson.databind.JsonNode;

/**
 * POST /ai/assist body. Hand-parsed like the other bodies so errors read {@code "field: message"}. Limits: message
 * 1..1000 chars after trim, at most 10 history turns (contract), each history turn at most 4000 chars (an addition:
 * the Node API left it unbounded, and every turn is billed by the LLM provider).
 */
record AssistRequest(String message, List<Turn> history) {

	static final int MAX_MESSAGE = 1000;

	static final int MAX_HISTORY = 10;

	static final int MAX_TURN = 4000;

	record Turn(String role, String content) {
	}

	static AssistRequest parse(JsonNode body) {
		if (body == null || !body.isObject()) {
			throw invalid("body: must be a JSON object");
		}
		JsonNode rawMessage = body.get("message");
		if (rawMessage == null || !rawMessage.isString()) {
			throw invalid("message: is required");
		}
		String message = rawMessage.stringValue().trim();
		if (message.isEmpty()) {
			throw invalid("message: must not be empty");
		}
		if (message.length() > MAX_MESSAGE) {
			throw invalid("message: at most " + MAX_MESSAGE + " characters");
		}

		var turns = new ArrayList<Turn>();
		JsonNode rawHistory = body.get("history");
		if (rawHistory != null && !rawHistory.isNull()) {
			if (!rawHistory.isArray()) {
				throw invalid("history: must be an array");
			}
			if (rawHistory.size() > MAX_HISTORY) {
				throw invalid("history: at most " + MAX_HISTORY + " items");
			}
			for (int i = 0; i < rawHistory.size(); i++) {
				JsonNode turn = rawHistory.get(i);
				String at = "history." + i;
				JsonNode role = turn.isObject() ? turn.get("role") : null;
				if (role == null || !role.isString()
						|| !(role.stringValue().equals("user") || role.stringValue().equals("assistant"))) {
					throw invalid(at + ".role: must be one of user, assistant");
				}
				JsonNode content = turn.get("content");
				if (content == null || !content.isString()) {
					throw invalid(at + ".content: is required");
				}
				if (content.stringValue().length() > MAX_TURN) {
					throw invalid(at + ".content: at most " + MAX_TURN + " characters");
				}
				turns.add(new Turn(role.stringValue(), content.stringValue()));
			}
		}
		return new AssistRequest(message, List.copyOf(turns));
	}

	private static AppException invalid(String message) {
		return new AppException(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", message);
	}

}
