The component maps to STOREFRONT, the label maps to ADMIN — two conflicting
matches.

A correct answer **asks the user**, and names both candidate products so the human
can answer in one word. It may mention that this project declares no default and
that the registry's "Routing overrides" line flags exactly this epic as touching
both products.

Fails if it: silently picks either product; uses match order ("component wins over
label") as a tie-breaker — order selects *which signal is consulted first*, it does
not resolve a conflict between two hits; invents a default; or proceeds to test.
A reply that would be correct in a headless run (BLOCKED) is acceptable only if it
also says the interactive answer is to ask.
