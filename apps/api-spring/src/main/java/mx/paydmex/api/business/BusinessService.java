package mx.paydmex.api.business;

import java.time.Clock;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

import jakarta.persistence.criteria.Predicate;

import mx.paydmex.api.auth.UserRepository;
import mx.paydmex.api.common.AppException;
import mx.paydmex.api.common.Clabe;
import mx.paydmex.api.pey.PeyClient;
import mx.paydmex.api.product.ProductDto;
import mx.paydmex.api.product.ProductService;

import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.data.domain.Sort;
import org.springframework.data.jpa.domain.Specification;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * Owner profile (create / update) and public discovery. The owner write paths are deliberately not one big
 * transaction: the pey HTTP call must not hold a pooled connection, so each DB step is its own short transaction.
 */
@Service
public class BusinessService {

	private final BusinessRepository businesses;

	private final UserRepository users;

	private final ProductService products;

	private final PeyClient pey;

	private final TransactionTemplate tx;

	private final Clock clock;

	BusinessService(BusinessRepository businesses, UserRepository users, ProductService products, PeyClient pey,
			TransactionTemplate tx, Clock clock) {
		this.businesses = businesses;
		this.users = users;
		this.products = products;
		this.pey = pey;
		this.tx = tx;
		this.clock = clock;
	}

	public BusinessDto create(String ownerId, CreateBusinessRequest req) {
		requireUser(ownerId);
		if (businesses.existsByOwnerId(ownerId)) {
			throw alreadyExists();
		}
		Business business = Business.create(ownerId, req, clock.instant().getEpochSecond());
		try {
			businesses.saveAndFlush(business);
		}
		catch (DataIntegrityViolationException ex) {
			// Lost a race with a concurrent create for the same owner (UNIQUE owner_id).
			throw alreadyExists();
		}
		return BusinessDto.from(business);
	}

	public BusinessDto update(String ownerId, UpdateBusinessRequest req) {
		requireUser(ownerId);
		Business current = businesses.findByOwnerId(ownerId).orElseThrow(BusinessService::businessNotFound);

		PeyClient.BankAccount account = null;
		String clabe = null;
		if (req.clabe().present()) {
			clabe = req.clabe().value();
			if (!Clabe.isValid(clabe)) {
				throw new AppException(HttpStatus.BAD_REQUEST, "INVALID_CLABE",
						"CLABE must be 18 digits with a valid check digit");
			}
			// Same CLABE already registered: nothing to tell pey.
			if (!clabe.equals(current.clabe()) || current.peyBankAccountId() == null) {
				String label = req.name().present() ? req.name().value().trim() : current.name();
				account = pey.registerBankAccount(label, label, clabe);
			}
		}

		PeyClient.BankAccount registered = account;
		String registeredClabe = clabe;
		return tx.execute(status -> {
			Business b = businesses.findById(current.id()).orElseThrow(BusinessService::businessNotFound);
			b.apply(req);
			if (registered != null) {
				b.registerBankAccount(registeredClabe, registered.id(), registered.codiStatus());
			}
			return BusinessDto.from(b);
		});
	}

	public List<PublicBusinessDto> listActive(String category, String prepType, String q) {
		validateFilter("category", category, BusinessTaxonomy.CATEGORIES, BusinessTaxonomy.CATEGORY_MESSAGE);
		validateFilter("prepType", prepType, BusinessTaxonomy.PREP_TYPES, BusinessTaxonomy.PREP_TYPE_MESSAGE);
		Specification<Business> spec = (root, query, cb) -> {
			List<Predicate> all = new ArrayList<>();
			all.add(cb.isTrue(root.get("active")));
			if (hasText(category)) {
				all.add(cb.equal(root.get("category"), category));
			}
			if (hasText(prepType)) {
				all.add(cb.equal(root.get("prepType"), prepType));
			}
			if (hasText(q)) {
				String pattern = "%" + escapeLike(q.trim().toLowerCase(Locale.ROOT)) + "%";
				all.add(cb.or(cb.like(cb.lower(root.<String>get("name")), pattern, '\\'),
						cb.like(cb.lower(cb.coalesce(root.<String>get("description"), "")), pattern, '\\'),
						cb.like(cb.lower(cb.coalesce(root.<String>get("address"), "")), pattern, '\\')));
			}
			return cb.and(all.toArray(Predicate[]::new));
		};
		// ULIDs sort by creation time, so this matches the Node API's insertion order.
		return businesses.findAll(spec, Sort.by("id")).stream().map(PublicBusinessDto::from).toList();
	}

	public PublicBusinessDto getActive(String id) {
		return businesses.findByIdAndActiveTrue(id)
			.map(PublicBusinessDto::from)
			.orElseThrow(BusinessService::businessNotFound);
	}

	public List<ProductDto> listActiveProducts(String businessId) {
		if (businesses.findByIdAndActiveTrue(businessId).isEmpty()) {
			throw businessNotFound();
		}
		return products.listActive(businessId);
	}

	/** A valid token for a deleted user is a 401 (same as /me and Node's requireAuth). */
	private void requireUser(String userId) {
		if (!users.existsById(userId)) {
			throw new AppException(HttpStatus.UNAUTHORIZED, "UNAUTHORIZED", "User not found");
		}
	}

	private static void validateFilter(String field, String value, java.util.Set<String> allowed, String message) {
		if (hasText(value) && !allowed.contains(value)) {
			throw new AppException(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", field + ": " + message);
		}
	}

	private static boolean hasText(String s) {
		return s != null && !s.isBlank();
	}

	/** Makes user input match literally in LIKE (the Node API let % and _ act as wildcards). */
	private static String escapeLike(String s) {
		return s.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_");
	}

	private static AppException alreadyExists() {
		return new AppException(HttpStatus.CONFLICT, "BUSINESS_ALREADY_EXISTS", "User already has a business");
	}

	private static AppException businessNotFound() {
		return new AppException(HttpStatus.NOT_FOUND, "BUSINESS_NOT_FOUND", "Business not found");
	}

}
