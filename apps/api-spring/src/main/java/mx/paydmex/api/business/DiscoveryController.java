package mx.paydmex.api.business;

import java.util.List;

import mx.paydmex.api.product.ProductDto;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Public discovery (no auth, see SecurityConfig). Never exposes clabe / peyBankAccountId. */
@RestController
class DiscoveryController {

	private final BusinessService service;

	DiscoveryController(BusinessService service) {
		this.service = service;
	}

	@GetMapping("/businesses")
	List<PublicBusinessDto> list(@RequestParam(required = false) String category,
			@RequestParam(required = false) String prepType, @RequestParam(required = false) String q) {
		return service.listActive(category, prepType, q);
	}

	@GetMapping("/businesses/{id}")
	PublicBusinessDto get(@PathVariable String id) {
		return service.getActive(id);
	}

	@GetMapping("/businesses/{id}/products")
	List<ProductDto> products(@PathVariable String id) {
		return service.listActiveProducts(id);
	}

}
