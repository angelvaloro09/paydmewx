package mx.paydmex.api.order;

import com.github.f4b6a3.ulid.UlidCreator;

import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PostLoad;
import jakarta.persistence.PostPersist;
import jakarta.persistence.Table;
import jakarta.persistence.Transient;

import org.springframework.data.domain.Persistable;

/** Line of an order with the name and unit price snapshotted at creation. Immutable once written. */
@Entity
@Table(name = "order_items")
public class OrderItem implements Persistable<String> {

	@Id
	private String id;

	private String orderId;

	private String productId;

	private String name;

	private long priceCents;

	private int qty;

	@Transient
	private boolean fresh = false;

	protected OrderItem() {
	}

	/** Monotonic ULID: lines of one order sort by id in the order they were requested. */
	static OrderItem create(String orderId, String productId, String name, long priceCents, int qty) {
		var i = new OrderItem();
		i.id = UlidCreator.getMonotonicUlid().toString();
		i.orderId = orderId;
		i.productId = productId;
		i.name = name;
		i.priceCents = priceCents;
		i.qty = qty;
		i.fresh = true;
		return i;
	}

	@Override
	public String getId() {
		return id;
	}

	@Override
	public boolean isNew() {
		return fresh;
	}

	@PostLoad
	@PostPersist
	void markPersisted() {
		this.fresh = false;
	}

	String id() {
		return id;
	}

	String orderId() {
		return orderId;
	}

	String productId() {
		return productId;
	}

	String name() {
		return name;
	}

	long priceCents() {
		return priceCents;
	}

	int qty() {
		return qty;
	}

}
