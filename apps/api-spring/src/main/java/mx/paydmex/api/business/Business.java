package mx.paydmex.api.business;

import com.github.f4b6a3.ulid.UlidCreator;

import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PostLoad;
import jakarta.persistence.PostPersist;
import jakarta.persistence.Table;
import jakarta.persistence.Transient;

import org.springframework.data.domain.Persistable;

/**
 * Merchant profile, one per owner (UNIQUE owner_id). Implements {@link Persistable} so the app-assigned ULID does
 * not trigger a select-before-insert. {@code createdAt} is unix SECONDS.
 */
@Entity
@Table(name = "businesses")
public class Business implements Persistable<String> {

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

	@Transient
	private boolean fresh = false;

	protected Business() {
	}

	static Business create(String ownerId, CreateBusinessRequest req, long createdAtSeconds) {
		var b = new Business();
		b.id = UlidCreator.getUlid().toString();
		b.ownerId = ownerId;
		b.name = req.name().trim();
		b.description = req.description();
		b.category = req.category();
		b.prepType = req.prepType();
		b.address = req.address();
		b.lat = req.lat();
		b.lng = req.lng();
		b.active = true;
		b.createdAt = createdAtSeconds;
		b.fresh = true;
		return b;
	}

	/** Applies the plain profile fields. The clabe is handled by {@link #registerBankAccount}. */
	void apply(UpdateBusinessRequest p) {
		if (p.name().present()) {
			name = p.name().value().trim();
		}
		if (p.category().present()) {
			category = p.category().value();
		}
		if (p.prepType().present()) {
			prepType = p.prepType().value();
		}
		if (p.description().present()) {
			description = p.description().value();
		}
		if (p.address().present()) {
			address = p.address().value();
		}
		if (p.lat().present()) {
			lat = p.lat().value();
		}
		if (p.lng().present()) {
			lng = p.lng().value();
		}
		if (p.active().present()) {
			active = p.active().value();
		}
	}

	void registerBankAccount(String clabe, String peyBankAccountId, String codiStatus) {
		this.clabe = clabe;
		this.peyBankAccountId = peyBankAccountId;
		this.codiStatus = codiStatus;
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

	@Override
	public String toString() {
		return "Business[id=" + id + "]";
	}

}
