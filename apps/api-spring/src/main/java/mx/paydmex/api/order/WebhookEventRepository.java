package mx.paydmex.api.order;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/**
 * Dedupe ledger of processed pey webhooks. The PK on {@code id} (= {@code webhook-id} header) is the mechanism:
 * {@code ON CONFLICT DO NOTHING} claims the id atomically without raising (a raised duplicate-key would abort the
 * surrounding Postgres transaction). Two concurrent deliveries of the same id: the second waits for the first to
 * commit and then sees the conflict.
 */
@Repository
class WebhookEventRepository {

	private final JdbcClient jdbc;

	WebhookEventRepository(JdbcClient jdbc) {
		this.jdbc = jdbc;
	}

	/** True when this call claimed the id (first delivery); false when it was already processed. */
	boolean claim(String webhookId, long receivedAtSeconds) {
		return jdbc.sql("INSERT INTO webhook_events (id, received_at) VALUES (?, ?) ON CONFLICT DO NOTHING")
			.params(webhookId, receivedAtSeconds)
			.update() == 1;
	}

}
