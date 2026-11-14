package mx.paydmex.api.auth;

import jakarta.validation.Valid;

import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
class AuthController {

	private final AuthService auth;

	AuthController(AuthService auth) {
		this.auth = auth;
	}

	@PostMapping("/auth/register")
	ResponseEntity<AuthResponse> register(@Valid @RequestBody RegisterRequest body) {
		return ResponseEntity.status(201).body(auth.register(body));
	}

	@PostMapping("/auth/login")
	AuthResponse login(@Valid @RequestBody LoginRequest body) {
		return auth.login(body);
	}

	@GetMapping("/me")
	MeResponse me(@AuthenticationPrincipal Jwt jwt) {
		return auth.profile(jwt.getSubject());
	}

}
