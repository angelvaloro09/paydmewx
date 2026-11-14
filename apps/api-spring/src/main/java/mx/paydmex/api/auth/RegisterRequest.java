package mx.paydmex.api.auth;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record RegisterRequest(
		@NotBlank(message = "is required") @Email(regexp = ".+@.+\\..+", message = "must be a valid email") String email,
		@Size(min = 8, message = "must be at least 8 characters") String password,
		@NotBlank(message = "is required") String name) {

	@Override
	public String toString() {
		return "RegisterRequest[email=" + email + "]";
	}

}
