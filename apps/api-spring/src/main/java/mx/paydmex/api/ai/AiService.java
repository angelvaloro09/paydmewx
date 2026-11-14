package mx.paydmex.api.ai;

import java.time.Clock;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;

import mx.paydmex.api.ai.LlmClient.LlmMessage;
import mx.paydmex.api.ai.LlmClient.LlmResponse;
import mx.paydmex.api.ai.LlmClient.LlmToolCall;
import mx.paydmex.api.auth.UserRepository;
import mx.paydmex.api.business.BusinessLookup;
import mx.paydmex.api.business.BusinessLookup.OwnBusiness;
import mx.paydmex.api.common.AppException;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

/**
 * Tool-calling loop. Deliberately NOT transactional: each tool call runs in the short transactions of the services it
 * uses, so no DB connection is held while waiting for the LLM. The role comes from the data, not from the model: a
 * user with a business gets the owner tools, everyone else the customer tools.
 */
@Service
public class AiService {

	static final int MAX_TOOL_ROUNDS = 4;

	private static final Pattern EMOJI = Pattern.compile("[\\p{IsExtended_Pictographic}\\x{FE0F}\\x{200D}]");

	private static final Pattern MARKDOWN = Pattern.compile("\\*\\*|__|`");

	private static final Pattern TRAILING_SPACE = Pattern.compile("[ \\t]+\\n");

	public record Result(String reply, List<AiAction> actions) {
	}

	private final LlmClient llm;

	private final AiToolExecutor tools;

	private final BusinessLookup businesses;

	private final UserRepository users;

	private final Clock clock;

	AiService(LlmClient llm, AiToolExecutor tools, BusinessLookup businesses, UserRepository users, Clock clock) {
		this.llm = llm;
		this.tools = tools;
		this.businesses = businesses;
		this.users = users;
		this.clock = clock;
	}

	Result assist(String userId, AssistRequest req) {
		if (!users.existsById(userId)) {
			throw new AppException(HttpStatus.UNAUTHORIZED, "UNAUTHORIZED", "User not found");
		}
		OwnBusiness business = businesses.findOwn(userId).orElse(null);
		var offered = business != null ? AiToolSpecs.OWNER : AiToolSpecs.CUSTOMER;
		var actions = new ArrayList<AiAction>();

		var messages = new ArrayList<LlmMessage>();
		messages.add(new LlmMessage.System(systemPrompt(business)));
		for (AssistRequest.Turn turn : req.history()) {
			messages.add(turn.role().equals("user") ? new LlmMessage.User(turn.content())
					: new LlmMessage.Assistant(turn.content(), List.of()));
		}
		messages.add(new LlmMessage.User(req.message()));

		String lastContent = null;
		for (int round = 0; round < MAX_TOOL_ROUNDS; round++) {
			LlmResponse response = llm.chat(List.copyOf(messages), offered);
			if (response.content() != null && !response.content().isEmpty()) {
				lastContent = response.content();
			}
			if (response.toolCalls().isEmpty()) {
				return new Result(sanitize(response.content()), List.copyOf(actions));
			}
			messages.add(new LlmMessage.Assistant(response.content(), response.toolCalls()));
			for (LlmToolCall call : response.toolCalls()) {
				String output = tools.execute(userId, business, call.name(), call.arguments(), actions);
				messages.add(new LlmMessage.Tool(call.id(), call.name(), output));
			}
		}
		String reply = sanitize(lastContent);
		return new Result(reply.isEmpty() ? "Listo." : reply, List.copyOf(actions));
	}

	private String systemPrompt(OwnBusiness business) {
		String today = clock.instant().atZone(AiToolExecutor.BUSINESS_ZONE).toLocalDate().toString();
		String role = business != null ? "owner (negocio: " + business.name() + ")" : "customer (cliente)";
		return String.join(" ", "Eres el asistente de PaydMex en CDMX.",
				"Responde en el idioma del usuario de forma breve y directa.",
				"Nunca inventes datos; usa siempre las herramientas disponibles.",
				"Para preguntas de inventario, stock o precios debes llamar a list_products.",
				"Escribe texto plano: sin emojis, sin markdown, sin negritas, maximo 3 frases cortas. Nunca muestres IDs ni codigos internos de ordenes.",
				"Nunca cobras dinero: record_sale solo crea una orden pendiente de pago (pending_payment).",
				"Fecha de hoy: " + today + ".", "Rol del usuario: " + role + ".");
	}

	/** Plain text for a chat bubble: no emoji, no markdown markers, no trailing blanks. */
	static String sanitize(String text) {
		if (text == null) {
			return "";
		}
		String s = EMOJI.matcher(text).replaceAll("");
		s = MARKDOWN.matcher(s).replaceAll("");
		return TRAILING_SPACE.matcher(s).replaceAll("\n").trim();
	}

}
