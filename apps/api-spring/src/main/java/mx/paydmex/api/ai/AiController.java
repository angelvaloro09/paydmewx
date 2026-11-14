package mx.paydmex.api.ai;

import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import tools.jackson.databind.JsonNode;

/** {@code POST /ai/assist}: authenticated (deny-by-default chain), rate limited before the body is validated. */
@RestController
class AiController {

	/** Contract shape: {@code {reply, actions[]}}. */
	record AssistResponse(String reply, java.util.List<AiAction> actions) {
	}

	private final AiService service;

	private final AiRateLimiter limiter;

	AiController(AiService service, AiRateLimiter limiter) {
		this.service = service;
		this.limiter = limiter;
	}

	@PostMapping("/ai/assist")
	AssistResponse assist(@AuthenticationPrincipal Jwt jwt, @RequestBody(required = false) JsonNode body) {
		String userId = jwt.getSubject();
		limiter.check(userId);
		AiService.Result result = service.assist(userId, AssistRequest.parse(body));
		return new AssistResponse(result.reply(), result.actions());
	}

}
