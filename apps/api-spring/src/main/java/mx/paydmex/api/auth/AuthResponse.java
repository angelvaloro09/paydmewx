package mx.paydmex.api.auth;

public record AuthResponse(String token, UserDto user) {

	@Override
	public String toString() {
		return "AuthResponse[user=" + user + "]";
	}

}
