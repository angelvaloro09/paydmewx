package mx.paydmex.api.auth;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;

public record LoginRequest(
		@NotBlank(message = "is required") @Email(regexp = ".+@.+\\..+", message = "must be a valid email") String email,
		@NotEmpty(message = "is required") String password) {

	@Override
	public String toString() {
		return "LoginRequest[email=" + email + "]";
	}

}
