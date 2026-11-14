package mx.paydmex.api.business;

import jakarta.validation.Valid;

import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import tools.jackson.databind.JsonNode;

/** Owner-facing profile routes (authenticated). */
@RestController
class BusinessController {

	private final BusinessService service;

	BusinessController(BusinessService service) {
		this.service = service;
	}

	@PostMapping("/me/business")
	ResponseEntity<BusinessDto> create(@AuthenticationPrincipal Jwt jwt, @Valid @RequestBody CreateBusinessRequest body) {
		return ResponseEntity.status(201).body(service.create(jwt.getSubject(), body));
	}

	@PatchMapping("/me/business")
	BusinessDto update(@AuthenticationPrincipal Jwt jwt, @RequestBody JsonNode body) {
		return service.update(jwt.getSubject(), UpdateBusinessRequest.parse(body));
	}

}
