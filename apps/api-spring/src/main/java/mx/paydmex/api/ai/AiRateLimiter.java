package mx.paydmex.api.ai;

import java.time.Clock;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.concurrent.ConcurrentHashMap;

import mx.paydmex.api.common.AppException;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

/**
 * Sliding window per user: at most {@value #MAX_REQUESTS} assistant calls in any {@value #WINDOW_MS} ms. In memory, so
 * it is per instance (the API runs as a single instance). Rejected calls are not counted, so a client that backs off
 * recovers as soon as its oldest call leaves the window.
 */
@Component
class AiRateLimiter {

	static final int MAX_REQUESTS = 20;

	static final long WINDOW_MS = 60_000;

	/** Above this many tracked users, stale entries are swept so the map cannot grow without bound. */
	private static final int SWEEP_THRESHOLD = 1_000;

	private final ConcurrentHashMap<String, Deque<Long>> calls = new ConcurrentHashMap<>();

	private final Clock clock;

	AiRateLimiter(Clock clock) {
		this.clock = clock;
	}

	/** Records a call for {@code userId} or throws 429 RATE_LIMITED. */
	void check(String userId) {
		long now = clock.millis();
		long cutoff = now - WINDOW_MS;
		boolean[] allowed = { true };
		calls.compute(userId, (id, window) -> {
			Deque<Long> recent = window == null ? new ArrayDeque<>() : window;
			while (!recent.isEmpty() && recent.peekFirst() <= cutoff) {
				recent.pollFirst();
			}
			if (recent.size() >= MAX_REQUESTS) {
				allowed[0] = false;
			}
			else {
				recent.addLast(now);
			}
			return recent.isEmpty() ? null : recent;
		});
		if (calls.size() > SWEEP_THRESHOLD) {
			// computeIfPresent is atomic per key, so it never races with check() mutating the same deque
			for (String id : calls.keySet()) {
				calls.computeIfPresent(id, (k, d) -> d.isEmpty() || d.peekLast() <= cutoff ? null : d);
			}
		}
		if (!allowed[0]) {
			throw new AppException(HttpStatus.TOO_MANY_REQUESTS, "RATE_LIMITED",
					"Demasiadas solicitudes al asistente. Intenta de nuevo en un minuto.");
		}
	}

}
