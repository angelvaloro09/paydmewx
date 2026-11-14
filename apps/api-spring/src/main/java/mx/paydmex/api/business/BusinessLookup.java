package mx.paydmex.api.business;

import java.util.Optional;

import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/** What the order/payment flow may know about a business, without exposing the entity. */
@Component
public class BusinessLookup {

	/** Only the fields orders need to authorize access and to route the CoDi charge. */
	public record BusinessRef(String id, String ownerId, boolean active, String peyBankAccountId, String codiStatus) {

		/** The charge goes to the merchant's own account only once pey reports the CoDi enrolment as ACTIVE. */
		public String codiBankAccountIdOrNull() {
			return "ACTIVE".equals(codiStatus) && peyBankAccountId != null && !peyBankAccountId.isBlank()
					? peyBankAccountId : null;
		}

	}

	private final BusinessRepository businesses;

	BusinessLookup(BusinessRepository businesses) {
		this.businesses = businesses;
	}

	@Transactional(readOnly = true)
	public Optional<BusinessRef> findById(String id) {
		return businesses.findById(id).map(BusinessLookup::ref);
	}

	@Transactional(readOnly = true)
	public Optional<BusinessRef> findActive(String id) {
		return businesses.findByIdAndActiveTrue(id).map(BusinessLookup::ref);
	}

	@Transactional(readOnly = true)
	public Optional<String> findIdByOwner(String ownerId) {
		return businesses.findByOwnerId(ownerId).map(Business::id);
	}

	@Transactional
	public int markCodiActive(String peyBankAccountId) {
		return businesses.markCodiActive(peyBankAccountId);
	}

	private static BusinessRef ref(Business b) {
		return new BusinessRef(b.id(), b.ownerId(), b.active(), b.peyBankAccountId(), b.codiStatus());
	}

}
