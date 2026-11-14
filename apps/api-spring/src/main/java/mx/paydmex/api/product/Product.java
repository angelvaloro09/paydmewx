package mx.paydmex.api.product;

import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/** Read-only mapping for now (public catalog). Phase 4 adds the owner CRUD and stock handling. */
@Entity
@Table(name = "products")
public class Product {

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

	protected Product() {
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

}
