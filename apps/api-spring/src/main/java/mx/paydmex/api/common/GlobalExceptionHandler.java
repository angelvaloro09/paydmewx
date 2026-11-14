package mx.paydmex.api.common;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.AuthenticationException;
import org.springframework.validation.FieldError;
import org.springframework.validation.ObjectError;
import org.springframework.web.HttpMediaTypeNotSupportedException;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.HandlerMethodValidationException;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.servlet.resource.NoResourceFoundException;

@RestControllerAdvice
public class GlobalExceptionHandler {

	private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

	@ExceptionHandler(AppException.class)
	ResponseEntity<ErrorResponse> handleApp(AppException ex) {
		return respond(ex.status(), ex.code(), ex.getMessage());
	}

	@ExceptionHandler(MethodArgumentNotValidException.class)
	ResponseEntity<ErrorResponse> handleBodyValidation(MethodArgumentNotValidException ex) {
		String message = "Invalid request payload";
		ObjectError first = ex.getBindingResult().getAllErrors().stream().findFirst().orElse(null);
		if (first instanceof FieldError fe) {
			message = fe.getField() + ": " + fe.getDefaultMessage();
		}
		else if (first != null) {
			message = String.valueOf(first.getDefaultMessage());
		}
		return respond(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", message);
	}

	@ExceptionHandler(HandlerMethodValidationException.class)
	ResponseEntity<ErrorResponse> handleParamValidation(HandlerMethodValidationException ex) {
		String message = ex.getParameterValidationResults().stream()
				.filter(r -> !r.getResolvableErrors().isEmpty())
				.findFirst()
				.map(r -> {
					String name = r.getMethodParameter().getParameterName();
					String msg = r.getResolvableErrors().get(0).getDefaultMessage();
					return (name != null ? name + ": " : "") + msg;
				})
				.orElse("Invalid request");
		return respond(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", message);
	}

	@ExceptionHandler({ HttpMessageNotReadableException.class, MissingServletRequestParameterException.class,
			MethodArgumentTypeMismatchException.class })
	ResponseEntity<ErrorResponse> handleBadRequest(Exception ex) {
		return respond(HttpStatus.BAD_REQUEST, "BAD_REQUEST", "Malformed request");
	}

	@ExceptionHandler(NoResourceFoundException.class)
	ResponseEntity<ErrorResponse> handleNotFound(NoResourceFoundException ex) {
		return respond(HttpStatus.NOT_FOUND, "NOT_FOUND", "Route not found");
	}

	@ExceptionHandler(HttpRequestMethodNotSupportedException.class)
	ResponseEntity<ErrorResponse> handleMethod(HttpRequestMethodNotSupportedException ex) {
		return respond(HttpStatus.METHOD_NOT_ALLOWED, "REQUEST_ERROR", "Method not allowed");
	}

	@ExceptionHandler(HttpMediaTypeNotSupportedException.class)
	ResponseEntity<ErrorResponse> handleMediaType(HttpMediaTypeNotSupportedException ex) {
		return respond(HttpStatus.UNSUPPORTED_MEDIA_TYPE, "REQUEST_ERROR", "Unsupported media type");
	}

	@ExceptionHandler(AuthenticationException.class)
	ResponseEntity<ErrorResponse> handleAuthentication(AuthenticationException ex) {
		return respond(HttpStatus.UNAUTHORIZED, "UNAUTHORIZED", "Unauthorized");
	}

	@ExceptionHandler(AccessDeniedException.class)
	ResponseEntity<ErrorResponse> handleAccessDenied(AccessDeniedException ex) {
		return respond(HttpStatus.FORBIDDEN, "FORBIDDEN", "Forbidden");
	}

	@ExceptionHandler(Exception.class)
	ResponseEntity<ErrorResponse> handleUnexpected(Exception ex) {
		log.error("Unhandled exception", ex);
		return respond(HttpStatus.INTERNAL_SERVER_ERROR, "INTERNAL_ERROR", "Internal server error");
	}

	private static ResponseEntity<ErrorResponse> respond(HttpStatus status, String code, String message) {
		return ResponseEntity.status(status).body(ErrorResponse.of(code, message));
	}

}
