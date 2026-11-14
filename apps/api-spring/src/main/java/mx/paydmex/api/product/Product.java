package mx.paydmex.api.product;

import com.github.f4b6a3.ulid.UlidCreator;

import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PostLoad;
import jakarta.persistence.PostPersist;
import jakarta.persistence.Table;
import jakarta.persistence.Transient;

import org.springframework.data.domain.Persistable;

/** Catalog item. Stock changes go through conditional UPDATEs in {@link ProductRepository}; money is centavos. */
@Entity
@Table(name = "products")
public class Product implements Persistable<String> {

	@Id
	private String id;

	private String businessId;

	private String name;

	private long priceCents;

	private boolean trackStock;

	private int stock;

	private Integer prepMinutes;

	private String imageUrl;

	private boolean active;

	private long createdAt;

	@Transient
	private boolean fresh = false;

	protected Product() {
	}

	static Product create(String businessId, CreateProductRequest req, long createdAtSeconds) {
		var p = new Product();
		p.id = UlidCreator.getUlid().toString();
		p.businessId = businessId;
		p.name = req.name().trim();
		p.priceCents = req.priceCents();
		p.trackStock = req.trackStock();
		p.stock = req.stock();
		p.prepMinutes = req.prepMinutes();
		p.imageUrl = req.imageUrl();
		p.active = true;
		p.createdAt = createdAtSeconds;
		p.fresh = true;
		return p;
	}

	/** Applies every present field except {@code stock}, which {@link ProductService} changes with a movement. */
	void apply(UpdateProductRequest p) {
		if (p.name().present()) {
			name = p.name().value().trim();
		}
		if (p.priceCents().present()) {
			priceCents = p.priceCents().value();
		}
		if (p.trackStock().present()) {
			trackStock = p.trackStock().value();
		}
		if (p.prepMinutes().present()) {
			prepMinutes = p.prepMinutes().value();
		}
		if (p.imageUrl().present()) {
			imageUrl = p.imageUrl().value();
		}
		if (p.active().present()) {
			active = p.active().value();
		}
	}

	void setStock(int stock) {
		this.stock = stock;
	}

	void deactivate() {
		this.active = false;
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

	String name() {
		return name;
	}

	long priceCents() {
		return priceCents;
	}

	boolean trackStock() {
		return trackStock;
	}

	int stock() {
		return stock;
	}

	Integer prepMinutes() {
		return prepMinutes;
	}

	String imageUrl() {
		return imageUrl;
	}

	boolean active() {
		return active;
	}

	long createdAt() {
		return createdAt;
	}

	@Override
	public String toString() {
		return "Product[id=" + id + "]";
	}

}
