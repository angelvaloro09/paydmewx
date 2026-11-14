package mx.paydmex.api.order;

import java.util.Collection;
import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface PaymentRepository extends JpaRepository<Payment, String> {

	/** Newest first, so the first row per order is its latest payment. */
	List<Payment> findByOrderIdInOrderByCreatedAtDescIdDesc(Collection<String> orderIds);

	List<Payment> findByOrderIdAndStatusOrderByCreatedAtDescIdDesc(String orderId, String status);

	Optional<Payment> findFirstByCodiQrId(String codiQrId);

	Optional<Payment> findFirstByOrderIdOrderByCreatedAtDescIdDesc(String orderId);

	@Modifying(flushAutomatically = true, clearAutomatically = true)
	@Query("update Payment p set p.status = 'paid' where p.id = :id")
	int markPaid(@Param("id") String id);

	@Modifying(flushAutomatically = true, clearAutomatically = true)
	@Query("update Payment p set p.status = 'paid', p.transactionId = :transactionId where p.id = :id")
	int markPaid(@Param("id") String id, @Param("transactionId") String transactionId);

	/** Pending QRs of orders that are now expired stop being payable. Idempotent. */
	@Modifying(flushAutomatically = true, clearAutomatically = true)
	@Query("""
			update Payment p set p.status = 'expired'
			where p.status = 'pending'
			  and p.orderId in (select o.id from PurchaseOrder o where o.id in :orderIds and o.status = 'expired')""")
	int expirePendingOfExpiredOrders(@Param("orderIds") Collection<String> orderIds);

}
