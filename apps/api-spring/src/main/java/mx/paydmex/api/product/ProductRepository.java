package mx.paydmex.api.product;

import java.util.List;

import org.springframework.data.jpa.repository.JpaRepository;

public interface ProductRepository extends JpaRepository<Product, String> {

	List<Product> findByBusinessIdAndActiveTrueOrderByIdAsc(String businessId);

}
