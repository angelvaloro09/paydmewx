package mx.paydmex.api.order;

import com.github.f4b6a3.ulid.UlidCreator;

import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PostLoad;
import jakarta.persistence.PostPersist;
import jakarta.persistence.Table;
import jakarta.persistence.Transient;

import org.springframework.data.domain.Persistable;

/**
 * Order header (table {@code orders}; named PurchaseOrder because ORDER is a JPQL keyword). Status changes never go
 * through this object: they are conditional UPDATEs in {@link OrderRepository}. Money is centavos, times are unix
 * SECONDS. {@code customerId} null = walk-in order created by the owner.
 */
@Entity
@Table(name = "orders")
public class PurchaseOrder implements Persistable<String> {

	@Id
	private String id;

	private String businessId;

	private String customerId;

	private String status;

	private long totalCents;

	private String note;

	private long createdAt;

	private Long paidAt;

	@Transient
	private boolean fresh = false;

	protected PurchaseOrder() {
	}

	static PurchaseOrder create(String businessId, String customerId, long totalCents, String note,
			long createdAtSeconds) {
		var o = new PurchaseOrder();
		o.id = UlidCreator.getUlid().toString();
		o.businessId = businessId;
		o.customerId = customerId;
		o.status = OrderStatus.PENDING_PAYMENT.wire();
		o.totalCents = totalCents;
		o.note = note;
		o.createdAt = createdAtSeconds;
		o.fresh = true;
		return o;
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

	String businessId() {
		return businessId;
	}

	String customerId() {
		return customerId;
	}

	String status() {
		return status;
	}

	long totalCents() {
		return totalCents;
	}

	String note() {
		return note;
	}

	long createdAt() {
		return createdAt;
	}

	Long paidAt() {
		return paidAt;
	}

	@Override
	public String toString() {
		return "PurchaseOrder[id=" + id + "]";
	}

}
