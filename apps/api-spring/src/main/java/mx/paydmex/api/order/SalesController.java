package mx.paydmex.api.order;

import mx.paydmex.api.common.AppException;

import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
class SalesController {

	private final SalesService service;

	SalesController(SalesService service) {
		this.service = service;
	}

	@GetMapping("/business/sales/summary")
	SalesSummaryDto summary(@AuthenticationPrincipal Jwt jwt,
			@RequestParam(name = "from", required = false) String from,
			@RequestParam(name = "to", required = false) String to) {
		return service.summary(jwt.getSubject(), seconds("from", from), seconds("to", to));
	}

	/** Blank or missing = no bound. Anything that is not an integer is a 400 (Node's zod int()). */
	private static Long seconds(String field, String raw) {
		if (raw == null || raw.isBlank()) {
			return null;
		}
		try {
			return Long.parseLong(raw.trim());
		}
		catch (NumberFormatException ex) {
			throw new AppException(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", field + ": must be an integer");
		}
	}

}
