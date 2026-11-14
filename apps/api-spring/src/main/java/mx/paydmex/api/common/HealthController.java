package mx.paydmex.api.common;

import java.util.Map;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
class HealthController {

	@GetMapping("/health")
	Map<String, Boolean> health() {
		return Map.of("ok", true);
	}

}
