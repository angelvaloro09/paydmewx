package mx.paydmex.api.common;

/** Wire shape of every error: {"error":{"code":"...","message":"..."}}. */
public record ErrorResponse(Body error) {

	public record Body(String code, String message) {
	}

	public static ErrorResponse of(String code, String message) {
		return new ErrorResponse(new Body(code, message));
	}

}
