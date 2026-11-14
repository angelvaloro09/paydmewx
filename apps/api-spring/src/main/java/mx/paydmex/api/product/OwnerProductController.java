package mx.paydmex.api.product;

import java.util.List;

import mx.paydmex.api.common.AppException;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import tools.jackson.databind.JsonNode;

/** Owner catalog and inventory routes. Every call is scoped to the caller's own business by the service. */
@RestController
class OwnerProductController {

	private static final int DEFAULT_LOW_STOCK_THRESHOLD = 5;

	private final ProductService service;

	OwnerProductController(ProductService service) {
		this.service = service;
	}

	@GetMapping("/business/products")
	List<ProductDto> list(@AuthenticationPrincipal Jwt jwt) {
		return service.listOwn(jwt.getSubject());
	}

	@PostMapping("/business/products")
	ResponseEntity<ProductDto> create(@AuthenticationPrincipal Jwt jwt, @RequestBody JsonNode body) {
		return ResponseEntity.status(201).body(service.create(jwt.getSubject(), CreateProductRequest.parse(body)));
	}

	@PatchMapping("/business/products/{id}")
	ProductDto update(@AuthenticationPrincipal Jwt jwt, @PathVariable String id, @RequestBody JsonNode body) {
		return service.update(jwt.getSubject(), id, UpdateProductRequest.parse(body));
	}

	@DeleteMapping("/business/products/{id}")
	ProductDto delete(@AuthenticationPrincipal Jwt jwt, @PathVariable String id) {
		return service.deactivate(jwt.getSubject(), id);
	}

	@PostMapping("/business/products/{id}/stock")
	StockAdjustmentDto adjustStock(@AuthenticationPrincipal Jwt jwt, @PathVariable String id,
			@RequestBody JsonNode body) {
		return service.adjustStock(jwt.getSubject(), id, AdjustStockRequest.parse(body));
	}

	@GetMapping("/business/inventory/low")
	List<ProductDto> lowStock(@AuthenticationPrincipal Jwt jwt,
			@RequestParam(name = "threshold", required = false) String threshold) {
		return service.lowStock(jwt.getSubject(), parseThreshold(threshold));
	}

	private static int parseThreshold(String raw) {
		if (raw == null || raw.isBlank()) {
			return DEFAULT_LOW_STOCK_THRESHOLD;
		}
		try {
			int value = Integer.parseInt(raw.trim());
			if (value >= 0) {
				return value;
			}
		}
		catch (NumberFormatException ex) {
			// falls through to the 400 below
		}
		throw new AppException(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR",
				"threshold: must be a non-negative integer");
	}

}
