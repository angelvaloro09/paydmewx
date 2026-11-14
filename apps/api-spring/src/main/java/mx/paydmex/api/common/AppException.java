package mx.paydmex.api.common;

import org.springframework.http.HttpStatus;

/** Business error rendered as {"error":{"code","message"}} by {@link GlobalExceptionHandler}. */
public class AppException extends RuntimeException {

	private final HttpStatus status;
	private final String code;

	public AppException(HttpStatus status, String code, String message) {
		super(message);
		this.status = status;
		this.code = code;
	}

	public HttpStatus status() {
		return status;
	}

	public String code() {
		return code;
	}

}
