package mx.paydmex.api.business;

import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * Read-only mapping for now (Phase 2 needs it for {@code GET /me}). Phase 3 adds creation/update and will make it
 * {@code Persistable<String>} like {@code User}.
 */
@Entity
@Table(name = "businesses")
public class Business {

	@Id
	private String id;

	private String ownerId;

	private String name;

	private String description;

	private String category;

	private String prepType;

	private String address;

	private Double lat;

	private Double lng;

	private boolean active;

	private String peyBankAccountId;

	private String clabe;

	private String codiStatus;

	private long createdAt;

	protected Business() {
	}

	String id() {
		return id;
	}

	String ownerId() {
		return ownerId;
	}

	String name() {
		return name;
	}

	String description() {
		return description;
	}

	String category() {
		return category;
	}

	String prepType() {
		return prepType;
	}

	String address() {
		return address;
	}

	Double lat() {
		return lat;
	}

	Double lng() {
		return lng;
	}

	boolean active() {
		return active;
	}

	String peyBankAccountId() {
		return peyBankAccountId;
	}

	String clabe() {
		return clabe;
	}

	String codiStatus() {
		return codiStatus;
	}

	long createdAt() {
		return createdAt;
	}

}
