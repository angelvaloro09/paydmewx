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
 * One CoDi charge attempt. {@code status} is free text in the DB ('pending' | 'paid' | 'expired'); it only changes via
 * conditional UPDATEs in {@link PaymentRepository}. {@code amountCents} is the ORDER total, even when
 * PEY_TEST_AMOUNT_OVERRIDE made pey charge less.
 */
@Entity
@Table(name = "payments")
public class Payment implements Persistable<String> {

	static final String PENDING = "pending";

	static final String PAID = "paid";

	static final String EXPIRED = "expired";

	@Id
	private String id;

	private String orderId;

	private String codiQrId;

	private String qrString;

	private Long expiresAt;

	private String transactionId;

	private String status;

	private long amountCents;

	private long createdAt;

	@Transient
	private boolean fresh = false;

	protected Payment() {
	}

	static Payment pending(String orderId, String codiQrId, String qrString, long expiresAt, long amountCents,
			long createdAtSeconds) {
		var p = new Payment();
		p.id = UlidCreator.getUlid().toString();
		p.orderId = orderId;
		p.codiQrId = codiQrId;
		p.qrString = qrString;
		p.expiresAt = expiresAt;
		p.status = PENDING;
		p.amountCents = amountCents;
		p.createdAt = createdAtSeconds;
		p.fresh = true;
		return p;
	}

	/** An order confirmed paid by a webhook that matched no QR we stored (metadata fallback). */
	static Payment paidWithoutQr(String orderId, String transactionId, long amountCents, long createdAtSeconds) {
		var p = new Payment();
		p.id = UlidCreator.getUlid().toString();
		p.orderId = orderId;
		p.transactionId = transactionId;
		p.status = PAID;
		p.amountCents = amountCents;
		p.createdAt = createdAtSeconds;
		p.fresh = true;
		return p;
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

	String codiQrId() {
		return codiQrId;
	}

	String qrString() {
		return qrString;
	}

	Long expiresAt() {
		return expiresAt;
	}

	String transactionId() {
		return transactionId;
	}

	String status() {
		return status;
	}

	long amountCents() {
		return amountCents;
	}

	long createdAt() {
		return createdAt;
	}

	@Override
	public String toString() {
		return "Payment[id=" + id + "]";
	}

}
