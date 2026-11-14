package mx.paydmex.api.order;

import java.util.Collection;
import java.util.List;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface OrderRepository extends JpaRepository<PurchaseOrder, String> {

	List<PurchaseOrder> findByCustomerIdOrderByCreatedAtDescIdDesc(String customerId);

	List<PurchaseOrder> findByBusinessIdOrderByCreatedAtDescIdDesc(String businessId);

	@Query("""
			select o from PurchaseOrder o
			where o.customerId = :userId or o.businessId = :businessId
			order by o.createdAt desc, o.id desc""")
	List<PurchaseOrder> findForCustomerOrBusiness(@Param("userId") String userId,
			@Param("businessId") String businessId);

	/** Pending orders created at or before {@code cutoff} (unix seconds) that belong to the user or the business. */
	@Query("""
			select o.id from PurchaseOrder o
			where o.status = 'pending_payment' and o.createdAt <= :cutoff
			  and (o.customerId = :userId or o.businessId = :businessId)""")
	List<String> findStaleIds(@Param("cutoff") long cutoff, @Param("userId") String userId,
			@Param("businessId") String businessId);

	/** Lazy expiry: only a still-pending, still-stale order flips (a concurrent payment wins). */
	@Modifying(flushAutomatically = true, clearAutomatically = true)
	@Query("""
			update PurchaseOrder o set o.status = 'expired'
			where o.id in :ids and o.status = 'pending_payment' and o.createdAt <= :cutoff""")
	int expireStale(@Param("ids") Collection<String> ids, @Param("cutoff") long cutoff);

	/**
	 * Payment confirmed. An 'expired' order is accepted too: the QR can be paid right at the edge and pey may deliver
	 * the webhook late, and the money is already collected. A cancelled order is NOT revived (needs a refund).
	 */
	@Modifying(flushAutomatically = true, clearAutomatically = true)
	@Query("""
			update PurchaseOrder o set o.status = 'paid', o.paidAt = :now
			where o.id = :id and o.status in ('pending_payment', 'expired')""")
	int markPaid(@Param("id") String id, @Param("now") long now);

}
