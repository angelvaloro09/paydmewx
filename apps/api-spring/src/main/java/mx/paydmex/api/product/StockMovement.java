package mx.paydmex.api.product;

import com.github.f4b6a3.ulid.UlidCreator;

import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PostLoad;
import jakarta.persistence.PostPersist;
import jakarta.persistence.Table;
import jakarta.persistence.Transient;

import org.springframework.data.domain.Persistable;

/** Append-only audit row: one per stock change. {@code createdAt} is unix SECONDS. */
@Entity
@Table(name = "stock_movements")
public class StockMovement implements Persistable<String> {

	@Id
	private String id;

	private String productId;

	private int delta;

	private String reason;

	private long createdAt;

	@Transient
	private boolean fresh = false;

	protected StockMovement() {
	}

	static StockMovement create(String productId, int delta, String reason, long createdAtSeconds) {
		var m = new StockMovement();
		m.id = UlidCreator.getUlid().toString();
		m.productId = productId;
		m.delta = delta;
		m.reason = reason;
		m.createdAt = createdAtSeconds;
		m.fresh = true;
		return m;
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

	String productId() {
		return productId;
	}

	int delta() {
		return delta;
	}

	String reason() {
		return reason;
	}

	long createdAt() {
		return createdAt;
	}

}
