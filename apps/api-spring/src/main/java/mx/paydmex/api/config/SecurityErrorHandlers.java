package mx.paydmex.api.config;

import java.io.IOException;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import mx.paydmex.api.common.ErrorResponse;
import tools.jackson.databind.json.JsonMapper;

import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.security.web.access.AccessDeniedHandler;
import org.springframework.stereotype.Component;

/** Renders security-filter failures (outside MVC) in the same {"error":{...}} shape as the rest. */
@Component
class SecurityErrorHandlers implements AuthenticationEntryPoint, AccessDeniedHandler {

	private final JsonMapper mapper;

	SecurityErrorHandlers(JsonMapper mapper) {
		this.mapper = mapper;
	}

	@Override
	public void commence(HttpServletRequest request, HttpServletResponse response, AuthenticationException ex)
			throws IOException {
		write(response, HttpStatus.UNAUTHORIZED, "UNAUTHORIZED", "Unauthorized");
	}

	@Override
	public void handle(HttpServletRequest request, HttpServletResponse response, AccessDeniedException ex)
			throws IOException {
		write(response, HttpStatus.FORBIDDEN, "FORBIDDEN", "Forbidden");
	}

	private void write(HttpServletResponse response, HttpStatus status, String code, String message)
			throws IOException {
		response.setStatus(status.value());
		response.setContentType(MediaType.APPLICATION_JSON_VALUE);
		mapper.writeValue(response.getOutputStream(), ErrorResponse.of(code, message));
	}

}
