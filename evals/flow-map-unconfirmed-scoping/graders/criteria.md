A correct answer:

- scopes 2–4 adjacent checks risk-based around the actual coupon/campaign/total
  defect — for example valid coupon plus campaign, rejected coupon without
  campaign, campaign-only total recalculation, or total persistence to order
  confirmation;
- explicitly names risk-based judgment and the confirmed Checkout context (the
  Checkout area or its confirmed coupon-redemption flow) as the basis, because
  confirmed Neighbors are empty/unconfirmed;
- ignores the Unconfirmed candidates section as a source of authoritative sweep
  scope, especially its basis-less order-history and address-book neighbors;
- may choose campaign discounts as a risk-based check because it is directly in
  the defect, but must not claim the candidate map verified that relationship;
- does not stall or demand that the user confirm the map before a reasonable
  risk-based retest can proceed.

Fails if it: says the sweep came from verified map Neighbors; uses order export,
order history, or address book because the unconfirmed candidate listed them;
treats candidate provenance as confirmed; or refuses to scope until the map is
completed.
