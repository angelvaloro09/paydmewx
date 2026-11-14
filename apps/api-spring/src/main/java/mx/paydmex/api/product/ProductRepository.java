package mx.paydmex.api.product;

import java.util.Collection;
import java.util.List;
import java.util.Optional;

import jakarta.persistence.LockModeType;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface ProductRepository extends JpaRepository<Product, String> {

	List<Product> findByBusinessIdAndActiveTrueOrderByIdAsc(String businessId);

	List<Product> findByBusinessIdOrderByIdAsc(String businessId);

	Optional<Product> findByIdAndBusinessId(String id, String businessId);

	/** Row lock for edits that read the current value (PATCH with an absolute stock needs the delta to log). */
	@Lock(LockModeType.PESSIMISTIC_WRITE)
	@Query("select p from Product p where p.id = :id and p.businessId = :businessId")
	Optional<Product> lockByIdAndBusinessId(@Param("id") String id, @Param("businessId") String businessId);

	@Query("""
			select p from Product p
			where p.businessId = :businessId and p.active = true and p.trackStock = true and p.stock <= :threshold
			order by p.stock asc, p.id asc""")
	List<Product> findLowStock(@Param("businessId") String businessId, @Param("threshold") int threshold);

	/**
	 * Atomic relative change: applies only if the result stays within [0, Integer.MAX_VALUE]. The bounds are checked
	 * in BIGINT so an oversized delta cannot overflow the INTEGER column. Returns 0 when nothing matched.
	 */
	@Modifying(flushAutomatically = true, clearAutomatically = true)
	@Query("""
			update Product p set p.stock = p.stock + :delta
			where p.id = :id and p.businessId = :businessId
			  and cast(p.stock as long) + :delta >= 0
			  and cast(p.stock as long) + :delta <= 2147483647""")
	int adjustStock(@Param("id") String id, @Param("businessId") String businessId, @Param("delta") long delta);

	List<Product> findByBusinessIdAndActiveTrueAndIdIn(String businessId, Collection<String> ids);

	/** Row lock for the oversell fallback of {@link StockLedger}. */
	@Lock(LockModeType.PESSIMISTIC_WRITE)
	@Query("select p from Product p where p.id = :id")
	Optional<Product> lockById(@Param("id") String id);

	/** Sale decrement: {@code WHERE stock >= :qty} makes the check and the write one atomic statement. */
	@Modifying(flushAutomatically = true, clearAutomatically = true)
	@Query("update Product p set p.stock = p.stock - :qty where p.id = :id and p.trackStock = true and p.stock >= :qty")
	int decrementIfEnough(@Param("id") String id, @Param("qty") int qty);

	/** Restock increment; the bound is checked in BIGINT so it cannot overflow the INTEGER column. */
	@Modifying(flushAutomatically = true, clearAutomatically = true)
	@Query("""
			update Product p set p.stock = p.stock + :qty
			where p.id = :id and p.trackStock = true and cast(p.stock as long) + :qty <= 2147483647""")
	int incrementIfFits(@Param("id") String id, @Param("qty") int qty);

}
