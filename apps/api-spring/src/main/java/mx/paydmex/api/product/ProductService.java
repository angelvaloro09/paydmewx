package mx.paydmex.api.product;

import java.time.Clock;
import java.util.List;

import mx.paydmex.api.business.OwnerBusinessResolver;
import mx.paydmex.api.common.AppException;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Public catalog plus the owner CRUD and stock operations. Owner methods take the caller's user id. */
@Service
public class ProductService {

	static final String MANUAL_EDIT_REASON = "manual_edit";

	static final String INITIAL_STOCK_REASON = "initial_stock";

	private final ProductRepository products;

	private final StockMovementRepository movements;

	private final OwnerBusinessResolver owners;

	private final Clock clock;

	ProductService(ProductRepository products, StockMovementRepository movements, OwnerBusinessResolver owners,
			Clock clock) {
		this.products = products;
		this.movements = movements;
		this.owners = owners;
		this.clock = clock;
	}

	@Transactional(readOnly = true)
	public List<ProductDto> listActive(String businessId) {
		return products.findByBusinessIdAndActiveTrueOrderByIdAsc(businessId).stream().map(ProductDto::from).toList();
	}

	@Transactional(readOnly = true)
	public List<ProductDto> listOwn(String userId) {
		String businessId = owners.requireBusinessId(userId);
		return products.findByBusinessIdOrderByIdAsc(businessId).stream().map(ProductDto::from).toList();
	}

	@Transactional
	public ProductDto create(String userId, CreateProductRequest req) {
		String businessId = owners.requireBusinessId(userId);
		Product product = Product.create(businessId, req, now());
		products.saveAndFlush(product);
		if (product.stock() > 0) {
			movements.save(StockMovement.create(product.id(), product.stock(), INITIAL_STOCK_REASON, now()));
		}
		return ProductDto.from(product);
	}

	/**
	 * Edits the profile fields. An absolute {@code stock} is applied under a row lock and logged as a
	 * {@code manual_edit} movement with the real delta, so the movement log always explains the current stock.
	 */
	@Transactional
	public ProductDto update(String userId, String productId, UpdateProductRequest req) {
		String businessId = owners.requireBusinessId(userId);
		Product p = products.lockByIdAndBusinessId(productId, businessId).orElseThrow(ProductService::notFound);
		p.apply(req);
		if (req.stock().present() && req.stock().value() != p.stock()) {
			int delta = req.stock().value() - p.stock();
			p.setStock(req.stock().value());
			movements.save(StockMovement.create(p.id(), delta, MANUAL_EDIT_REASON, now()));
		}
		return ProductDto.from(p);
	}

	/** Soft delete: active=false. Idempotent; the row and its history stay. */
	@Transactional
	public ProductDto deactivate(String userId, String productId) {
		String businessId = owners.requireBusinessId(userId);
		Product p = products.lockByIdAndBusinessId(productId, businessId).orElseThrow(ProductService::notFound);
		p.deactivate();
		return ProductDto.from(p);
	}

	/** Conditional UPDATE (no read-then-write) plus the movement row, in one transaction. */
	@Transactional
	public StockAdjustmentDto adjustStock(String userId, String productId, AdjustStockRequest req) {
		String businessId = owners.requireBusinessId(userId);
		if (products.adjustStock(productId, businessId, req.delta()) == 0) {
			products.findByIdAndBusinessId(productId, businessId).orElseThrow(ProductService::notFound);
			if (req.delta() < 0) {
				throw new AppException(HttpStatus.BAD_REQUEST, "INSUFFICIENT_STOCK",
						"Resulting stock cannot be negative");
			}
			throw new AppException(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR",
					"delta: resulting stock exceeds " + Integer.MAX_VALUE);
		}
		StockMovement movement = movements.save(StockMovement.create(productId, req.delta(), req.reason(), now()));
		Product p = products.findByIdAndBusinessId(productId, businessId).orElseThrow(ProductService::notFound);
		return StockAdjustmentDto.of(ProductDto.from(p), StockMovementDto.from(movement));
	}

	@Transactional(readOnly = true)
	public List<ProductDto> lowStock(String userId, int threshold) {
		String businessId = owners.requireBusinessId(userId);
		return products.findLowStock(businessId, threshold).stream().map(ProductDto::from).toList();
	}

	private long now() {
		return clock.instant().getEpochSecond();
	}

	private static AppException notFound() {
		return new AppException(HttpStatus.NOT_FOUND, "PRODUCT_NOT_FOUND", "Product not found");
	}

}
