package mx.paydmex.api.common;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;

import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

/** Test-only endpoints that exercise the error contract and the JWT filter. */
@RestController
class ProbeController {

	record ProbeRequest(@NotBlank String name, @Min(1) int qty) {
	}

	@PostMapping("/_probe/validate")
	ProbeRequest validate(@Valid @RequestBody ProbeRequest body) {
		return body;
	}

	@GetMapping("/_probe/app")
	void app() {
		throw new AppException(HttpStatus.CONFLICT, "EMAIL_EXISTS", "Email already registered");
	}

	@GetMapping("/_probe/boom")
	void boom() {
		throw new IllegalStateException("secret internal detail");
	}

	@GetMapping("/_probe/me")
	String me(@AuthenticationPrincipal Jwt jwt) {
		return jwt.getSubject() + "|" + jwt.getClaimAsString("email");
	}

}
