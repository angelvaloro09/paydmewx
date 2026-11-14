package mx.paydmex.api.auth;

import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.util.Locale;

import mx.paydmex.api.business.BusinessDto;
import mx.paydmex.api.business.BusinessRepository;
import mx.paydmex.api.common.AppException;

import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Register / login / profile. Register and login are intentionally NOT wrapped in one transaction: BCrypt takes
 * ~100ms and must not hold a pooled connection; each repository call is its own short transaction.
 */
@Service
public class AuthService {

	/** BCrypt ignores input past 72 bytes (and Spring Security rejects it). */
	private static final int BCRYPT_MAX_BYTES = 72;

	private final UserRepository users;

	private final BusinessRepository businesses;

	private final PasswordEncoder encoder;

	private final JwtService jwt;

	private final Clock clock;

	/** Compared against when the email is unknown so login timing does not reveal registered emails. */
	private final String timingDecoyHash;

	AuthService(UserRepository users, BusinessRepository businesses, PasswordEncoder encoder, JwtService jwt,
			Clock clock) {
		this.users = users;
		this.businesses = businesses;
		this.encoder = encoder;
		this.jwt = jwt;
		this.clock = clock;
		this.timingDecoyHash = encoder.encode("timing-decoy-not-a-real-password");
	}

	public AuthResponse register(RegisterRequest req) {
		if (tooLongForBcrypt(req.password())) {
			throw new AppException(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR",
					"password: must be at most 72 bytes");
		}
		String email = normalize(req.email());
		if (users.existsByEmail(email)) {
			throw emailExists();
		}
		var user = User.create(email, encoder.encode(req.password()), req.name().trim(),
				clock.instant().getEpochSecond());
		try {
			users.saveAndFlush(user);
		}
		catch (DataIntegrityViolationException ex) {
			// Lost a race with a concurrent register of the same email (UNIQUE constraint).
			throw emailExists();
		}
		return respond(user);
	}

	public AuthResponse login(LoginRequest req) {
		User user = users.findByEmail(normalize(req.email())).orElse(null);
		String hash = user != null ? user.getPasswordHash() : timingDecoyHash;
		boolean matches = !tooLongForBcrypt(req.password()) && encoder.matches(req.password(), hash);
		if (user == null || !matches) {
			throw new AppException(HttpStatus.UNAUTHORIZED, "INVALID_CREDENTIALS", "Invalid email or password");
		}
		return respond(user);
	}

	@Transactional(readOnly = true)
	public MeResponse profile(String userId) {
		// A valid token for a deleted user is a 401 (same as Node's requireAuth), not a 404.
		User user = users.findById(userId)
			.orElseThrow(() -> new AppException(HttpStatus.UNAUTHORIZED, "UNAUTHORIZED", "User not found"));
		BusinessDto business = businesses.findByOwnerId(userId).map(BusinessDto::from).orElse(null);
		return new MeResponse(UserDto.from(user), business);
	}

	private AuthResponse respond(User user) {
		return new AuthResponse(jwt.issue(user.getId(), user.getEmail()), UserDto.from(user));
	}

	private static AppException emailExists() {
		return new AppException(HttpStatus.CONFLICT, "EMAIL_EXISTS", "Email is already registered");
	}

	private static String normalize(String email) {
		return email.trim().toLowerCase(Locale.ROOT);
	}

	private static boolean tooLongForBcrypt(String password) {
		return password.getBytes(StandardCharsets.UTF_8).length > BCRYPT_MAX_BYTES;
	}

}
