package mx.paydmex.api;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

/** Boots the full context on H2 (PostgreSQL mode): Flyway V1 + ddl-auto=validate + properties binding. */
@SpringBootTest
@ActiveProfiles("test")
class PaydmexApiApplicationTests {

	@Test
	void contextLoads() {
	}

}
