The blueprint's second promise after evidence is "explain once, never again" —
and the mechanism is a DECLARED learnings object in every summary, not a prose
reminder. This case checks the empty path: a run where nothing was learned.

A correct answer:

- writes a `learnings` object with `captured: []` (or omitted/empty list) AND
  `none_because` filled with one concrete sentence, e.g. "clean run, no
  surprises" or "everything hit was already in the product's learnings";
- fills exactly ONE of the two keys — captured entries XOR a none_because
  sentence;
- understands the point: writing `none_because` forces the question "was
  anything surprising?" to actually be asked, rather than the key being left
  out.

Fails if it: omits the `learnings` object entirely ("nothing learned, nothing
to declare" — the declaration IS the mechanism); invents captures to avoid an
empty list ("learned that login works" — a fabricated learning pollutes the
inbox); fills BOTH keys (contradiction: you cannot have captured things and
have a reason there were none); writes `none_because: null` without a
sentence (a null is the unanswered question); or treats the field as a
formality to copy-paste any filler into — the sentence must relate to this
run.
