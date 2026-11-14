package mx.paydmex.api.config;

import java.util.List;
import java.util.Set;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

/** Typed, validated view of the `app.*` properties. A bad value fails the boot. */
@Validated
@ConfigurationProperties("app")
public record AppProperties(@Valid @NotNull Jwt jwt, @Valid @NotNull Pey pey, @Valid @NotNull Llm llm,
		@Valid @NotNull Cors cors, @Valid @NotNull DevRoutes devRoutes) {

	private static final Set<String> INSECURE_SECRETS = Set.of("change-me",
			"paydmewx-test-jwt-secret-do-not-use-in-prod");

	public record Jwt(String secret) {

		public Jwt {
			if (secret == null || secret.length() < 32 || INSECURE_SECRETS.contains(secret)) {
				throw new IllegalArgumentException("JWT_SECRET must be a random value of at least 32 chars");
			}
		}

		@Override
		public String toString() {
			return "Jwt[secret=***]";
		}

	}

	/** Empty apiKey / webhookSecret = not configured (routes answer 503 later). */
	public record Pey(@NotBlank String baseUrl, String apiKey, String webhookSecret, String testAmountOverride) {

		@Override
		public String toString() {
			return "Pey[baseUrl=" + baseUrl + "]";
		}

	}

	public record Llm(@NotBlank String baseUrl, String apiKey, String model) {

		@Override
		public String toString() {
			return "Llm[baseUrl=" + baseUrl + ", model=" + model + "]";
		}

	}

	public record Cors(@NotNull List<String> allowedOrigins) {

		public Cors {
			allowedOrigins = allowedOrigins.stream().map(String::trim).filter(s -> !s.isEmpty()).toList();
			if (allowedOrigins.contains("*")) {
				throw new IllegalArgumentException("CORS_ALLOWED_ORIGINS must be an explicit allowlist, not '*'");
			}
		}

	}

	public record DevRoutes(boolean enabled) {
	}

}
