A correct answer:

- names **STOREFRONT** as the product (the `Checkout` component maps to it in the
  project's `## Products` registry);
- lists reading `projects/EXAMPLE/PROJECT.md` and `learnings.md` **plus**
  `products/STOREFRONT/PRODUCT.md` and its `learnings.md` — not the ADMIN files;
- says the resolution came from the JIRA **component** (`product_routed_by:
  component`), not from the summary text.

Fails if it: picks ADMIN; claims it must ask the user (a single clean component
match is decisive); reads both products' files; or justifies the choice with the
words in the summary ("voucher" sounds like shopping) instead of the component.
