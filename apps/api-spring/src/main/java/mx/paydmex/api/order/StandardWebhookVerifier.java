package mx.paydmex.api.order;

import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.time.Clock;
import java.util.Base64;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

import mx.paydmex.api.common.AppException;
import mx.paydmex.api.config.AppProperties;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

/**
 * Standard Webhooks verification (what pey sends): {@code webhook-signature} holds space separated
 * {@code v1,<base64 HMAC-SHA256>} over {@code "<id>.<timestamp>.<raw body>"}, keyed with the base64 decoded
 * {@code whsec_...} secret. The HMAC is computed over the raw request BYTES (never a re-serialized body) and compared
 * with {@link MessageDigest#isEqual}, which is constant time, so the signature cannot be guessed byte by byte.
 */
@Component
class StandardWebhookVerifier {

	static final long TOLERANCE_SECONDS = 5 * 60;

	private static final String SECRET_PREFIX = "whsec_";

	private final byte[] secret;

	private final Clock clock;

	StandardWebhookVerifier(AppProperties props, Clock clock) {
		this.secret = decodeSecret(props.pey().webhookSecret());
		this.clock = clock;
	}

	/** Returns the verified {@code webhook-id}, or throws 503 (no secret) / 401 INVALID_SIGNATURE. */
	String verify(String webhookId, String timestamp, String signatureHeader, byte[] rawBody) {
		if (secret.length == 0) {
			throw new AppException(HttpStatus.SERVICE_UNAVAILABLE, "WEBHOOK_NOT_CONFIGURED",
					"PEY_WEBHOOK_SECRET is not configured");
		}
		String id = trim(webhookId);
		String ts = trim(timestamp);
		String header = trim(signatureHeader);
		if (id.isEmpty() || ts.isEmpty() || header.isEmpty()) {
			throw invalid("Missing Standard Webhooks headers");
		}
		if (!ts.matches("\\d{1,15}")) {
			throw invalid("Invalid webhook-timestamp header");
		}
		if (Math.abs(clock.instant().getEpochSecond() - Long.parseLong(ts)) > TOLERANCE_SECONDS) {
			throw invalid("Webhook timestamp outside 5-minute tolerance");
		}

		byte[] expected = Base64.getEncoder().encode(hmac(id, ts, rawBody == null ? new byte[0] : rawBody));
		boolean matched = false;
		for (String part : header.split("\\s+")) {
			if (!part.startsWith("v1,") || part.length() == 3) {
				continue;
			}
			// no early exit on a match: the time spent does not depend on which candidate was right
			matched |= MessageDigest.isEqual(expected, part.substring(3).getBytes(StandardCharsets.UTF_8));
		}
		if (!matched) {
			throw invalid("Webhook signature verification failed");
		}
		return id;
	}

	private byte[] hmac(String id, String timestamp, byte[] body) {
		try {
			Mac mac = Mac.getInstance("HmacSHA256");
			mac.init(new SecretKeySpec(secret, "HmacSHA256"));
			mac.update(id.getBytes(StandardCharsets.UTF_8));
			mac.update((byte) '.');
			mac.update(timestamp.getBytes(StandardCharsets.UTF_8));
			mac.update((byte) '.');
			return mac.doFinal(body);
		}
		catch (GeneralSecurityException ex) {
			throw new IllegalStateException("HmacSHA256 unavailable", ex);
		}
	}

	/** Blank = not configured (empty array). The MIME decoder skips stray characters, like Node's Buffer.from. */
	private static byte[] decodeSecret(String configured) {
		String s = trim(configured);
		if (s.startsWith(SECRET_PREFIX)) {
			s = s.substring(SECRET_PREFIX.length());
		}
		return s.isEmpty() ? new byte[0] : Base64.getMimeDecoder().decode(s);
	}

	private static String trim(String s) {
		return s == null ? "" : s.trim();
	}

	private static AppException invalid(String message) {
		return new AppException(HttpStatus.UNAUTHORIZED, "INVALID_SIGNATURE", message);
	}

}
