package mx.paydmex.api.business;

import mx.paydmex.api.auth.UserRepository;
import mx.paydmex.api.common.AppException;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

/**
 * Node's {@code requireAuth + requireBusiness} for owner routes: a valid token for a deleted user is 401, a user
 * without a business is 404 BUSINESS_NOT_FOUND. Returns the id of the caller's own business, so owner routes can
 * never touch another business.
 */
@Component
public class OwnerBusinessResolver {

	private final UserRepository users;

	private final BusinessRepository businesses;

	OwnerBusinessResolver(UserRepository users, BusinessRepository businesses) {
		this.users = users;
		this.businesses = businesses;
	}

	public String requireBusinessId(String userId) {
		if (!users.existsById(userId)) {
			throw new AppException(HttpStatus.UNAUTHORIZED, "UNAUTHORIZED", "User not found");
		}
		return businesses.findByOwnerId(userId)
			.map(Business::id)
			.orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "BUSINESS_NOT_FOUND",
					"User does not have a registered business"));
	}

}
