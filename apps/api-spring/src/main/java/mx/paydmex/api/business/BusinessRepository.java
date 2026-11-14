package mx.paydmex.api.business;

import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface BusinessRepository extends JpaRepository<Business, String>, JpaSpecificationExecutor<Business> {

	Optional<Business> findByOwnerId(String ownerId);

	boolean existsByOwnerId(String ownerId);

	Optional<Business> findByIdAndActiveTrue(String id);

	/** {@code bank.account.updated} webhook: pey finished the CoDi enrolment of that account. */
	@Modifying(flushAutomatically = true, clearAutomatically = true)
	@Query("update Business b set b.codiStatus = 'ACTIVE' where b.peyBankAccountId = :bankAccountId")
	int markCodiActive(@Param("bankAccountId") String bankAccountId);

}
