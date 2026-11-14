package mx.paydmex.api.auth;

/** Public user shape of docs/API_CONTRACT.md. Never carries the password hash. */
public record UserDto(String id, String email, String name, long createdAt) {

	static UserDto from(User user) {
		return new UserDto(user.getId(), user.getEmail(), user.getName(), user.getCreatedAt());
	}

}
