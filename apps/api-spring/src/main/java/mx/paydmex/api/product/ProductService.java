package mx.paydmex.api.product;

import java.util.List;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Phase 3 only exposes the public catalog; Phase 4 adds the owner CRUD and stock operations here. */
@Service
public class ProductService {

	private final ProductRepository products;

	ProductService(ProductRepository products) {
		this.products = products;
	}

	@Transactional(readOnly = true)
	public List<ProductDto> listActive(String businessId) {
		return products.findByBusinessIdAndActiveTrueOrderByIdAsc(businessId).stream().map(ProductDto::from).toList();
	}

}
