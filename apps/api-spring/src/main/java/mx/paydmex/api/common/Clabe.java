package mx.paydmex.api.common;

/** Mexican CLABE check: 18 digits, mod-10 check digit with weights 3, 7, 1 (same algorithm as the Node API). */
public final class Clabe {

	private static final int[] WEIGHTS = { 3, 7, 1 };

	private Clabe() {
	}

	public static boolean isValid(String clabe) {
		if (clabe == null || clabe.length() != 18) {
			return false;
		}
		int sum = 0;
		for (int i = 0; i < 18; i++) {
			char c = clabe.charAt(i);
			if (c < '0' || c > '9') {
				return false;
			}
			if (i < 17) {
				sum += ((c - '0') * WEIGHTS[i % 3]) % 10;
			}
		}
		int expected = (10 - (sum % 10)) % 10;
		return expected == clabe.charAt(17) - '0';
	}

}
