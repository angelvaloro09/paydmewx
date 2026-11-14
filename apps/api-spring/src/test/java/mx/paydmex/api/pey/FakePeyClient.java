package mx.paydmex.api.pey;

import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;

import mx.paydmex.api.common.AppException;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;

/** Test double: records calls, never touches the network. Import {@link Config} to replace HttpPeyClient. */
public class FakePeyClient implements PeyClient {

	public record Call(String alias, String name, String clabe) {
	}

	public final List<Call> calls = new CopyOnWriteArrayList<>();

	/** When set, every call throws it. */
	public volatile AppException failure;

	@Override
	public BankAccount registerBankAccount(String alias, String name, String clabe) {
		calls.add(new Call(alias, name, clabe));
		if (failure != null) {
			throw failure;
		}
		return new BankAccount("ba_fake_" + calls.size(), "PENDING");
	}

	public void reset() {
		calls.clear();
		failure = null;
	}

	@TestConfiguration
	public static class Config {

		@Bean
		@Primary
		FakePeyClient fakePeyClient() {
			return new FakePeyClient();
		}

	}

}
