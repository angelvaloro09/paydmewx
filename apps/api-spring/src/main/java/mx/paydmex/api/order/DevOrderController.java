package mx.paydmex.api.order;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

/** Dev-only (app.dev-routes.enabled=true, never in prod): marks an order paid without pey, like the Node API. */
@RestController
@ConditionalOnProperty(name = "app.dev-routes.enabled", havingValue = "true")
class DevOrderController {

	private final PeyWebhookService webhook;

	private final OrderService orders;

	DevOrderController(PeyWebhookService webhook, OrderService orders) {
		this.webhook = webhook;
		this.orders = orders;
	}

	@PostMapping("/dev/orders/{id}/simulate-paid")
	OrderDto simulatePaid(@PathVariable String id) {
		webhook.simulatePaid(id);
		return orders.getUnchecked(id);
	}

}
