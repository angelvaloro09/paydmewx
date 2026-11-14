package mx.paydmex.api.auth;

import com.github.f4b6a3.ulid.UlidCreator;

import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PostLoad;
import jakarta.persistence.PostPersist;
import jakarta.persistence.Table;
import jakarta.persistence.Transient;

import org.springframework.data.domain.Persistable;

/**
 * Account. Implements {@link Persistable} so the app-assigned ULID does not trigger a select-before-insert.
 * Columns map to snake_case via Spring's naming strategy; {@code createdAt} is unix SECONDS.
 */
@Entity
@Table(name = "users")
public class User implements Persistable<String> {

	@Id
	private String id;

	private String email;

	private String passwordHash;

	private String name;

	private long createdAt;

	@Transient
	private boolean fresh = false;

	protected User() {
	}

	public static User create(String email, String passwordHash, String name, long createdAtSeconds) {
		var user = new User();
		user.id = UlidCreator.getUlid().toString();
		user.email = email;
		user.passwordHash = passwordHash;
		user.name = name;
		user.createdAt = createdAtSeconds;
		user.fresh = true;
		return user;
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

	public String getEmail() {
		return email;
	}

	public String getPasswordHash() {
		return passwordHash;
	}

	public String getName() {
		return name;
	}

	public long getCreatedAt() {
		return createdAt;
	}

	@Override
	public String toString() {
		return "User[id=" + id + "]";
	}

}
