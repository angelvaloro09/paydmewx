package mx.paydmex.api;

import org.springframework.boot.SpringApplication;

public class TestPaydmexApiApplication {

	public static void main(String[] args) {
		SpringApplication.from(PaydmexApiApplication::main).with(TestcontainersConfiguration.class).run(args);
	}

}
