package mx.paydmex.api.order;

import java.util.List;

import mx.paydmex.api.common.AppException;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import tools.jackson.databind.JsonNode;

/** Order routes. Authorization (owner of the business or the order's customer) lives in {@link OrderService}. */
@RestController
class OrderController {

	private final OrderService service;

	OrderController(OrderService service) {
		this.service = service;
	}

	@PostMapping("/orders")
	ResponseEntity<OrderDto> create(@AuthenticationPrincipal Jwt jwt, @RequestBody JsonNode body) {
		return ResponseEntity.status(201).body(service.create(jwt.getSubject(), CreateOrderRequest.parse(body)));
	}

	@GetMapping("/orders")
	List<OrderDto> list(@AuthenticationPrincipal Jwt jwt, @RequestParam(name = "role", required = false) String role,
			@RequestParam(name = "status", required = false) String status) {
		return service.list(jwt.getSubject(), parseRole(role), parseStatus(status));
	}

	@GetMapping("/orders/{id}")
	OrderDto get(@AuthenticationPrincipal Jwt jwt, @PathVariable String id) {
		return service.get(jwt.getSubject(), id);
	}

	@PostMapping("/orders/{id}/pay")
	PayResponse pay(@AuthenticationPrincipal Jwt jwt, @PathVariable String id) {
		return service.pay(jwt.getSubject(), id);
	}

	/** Absent = both roles. Anything but customer|business (even empty) is a 400, like the Node zod enum. */
	private static OrderService.Role parseRole(String raw) {
		if (raw == null) {
			return null;
		}
		return switch (raw) {
			case "customer" -> OrderService.Role.CUSTOMER;
			case "business" -> OrderService.Role.BUSINESS;
			default -> throw new AppException(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR",
					"role: must be one of customer, business");
		};
	}

	/** Blank or missing = no filter (Node maps '' to undefined); an unknown status is a 400. */
	private static OrderStatus parseStatus(String raw) {
		if (raw == null || raw.isEmpty()) {
			return null;
		}
		return OrderStatus.fromWire(raw)
			.orElseThrow(() -> new AppException(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR",
					"status: must be a valid order status"));
	}

}
