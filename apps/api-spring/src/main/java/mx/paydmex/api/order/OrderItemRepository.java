package mx.paydmex.api.order;

import java.util.Collection;
import java.util.List;

import org.springframework.data.jpa.repository.JpaRepository;

public interface OrderItemRepository extends JpaRepository<OrderItem, String> {

	List<OrderItem> findByOrderIdInOrderByIdAsc(Collection<String> orderIds);

	List<OrderItem> findByOrderIdOrderByIdAsc(String orderId);

}
