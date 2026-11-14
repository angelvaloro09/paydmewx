package mx.paydmex.api.business;

import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

public interface BusinessRepository extends JpaRepository<Business, String> {

	Optional<Business> findByOwnerId(String ownerId);

}
