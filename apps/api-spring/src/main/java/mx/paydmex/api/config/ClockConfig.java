package mx.paydmex.api.config;

import java.time.Clock;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
class ClockConfig {

	/** Single time source so tests can pin it. */
	@Bean
	Clock clock() {
		return Clock.systemUTC();
	}

}
