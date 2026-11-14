package mx.paydmex.api.auth;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;

import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.JwsHeader;
import org.springframework.security.oauth2.jwt.JwtClaimsSet;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.JwtEncoderParameters;
import org.springframework.stereotype.Service;

/** Issues HS256 tokens with the same claims as the Node API: {@code sub}, {@code email}, {@code iat}, {@code exp} (7d). */
@Service
public class JwtService {

	static final Duration TTL = Duration.ofDays(7);

	private final JwtEncoder encoder;

	private final Clock clock;

	JwtService(JwtEncoder encoder, Clock clock) {
		this.encoder = encoder;
		this.clock = clock;
	}

	public String issue(String userId, String email) {
		Instant now = clock.instant();
		var claims = JwtClaimsSet.builder()
			.subject(userId)
			.claim("email", email)
			.issuedAt(now)
			.expiresAt(now.plus(TTL))
			.build();
		var header = JwsHeader.with(MacAlgorithm.HS256).build();
		return encoder.encode(JwtEncoderParameters.from(header, claims)).getTokenValue();
	}

}
