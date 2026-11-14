package mx.paydmex.api.business;

import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;

public interface BusinessRepository extends JpaRepository<Business, String>, JpaSpecificationExecutor<Business> {

	Optional<Business> findByOwnerId(String ownerId);

	boolean existsByOwnerId(String ownerId);

	Optional<Business> findByIdAndActiveTrue(String id);

}
