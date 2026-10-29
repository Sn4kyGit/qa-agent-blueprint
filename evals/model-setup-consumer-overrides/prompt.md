An opencode consumer session at `/work/consumer` already has an `opencode.json`
with MCP servers, permissions, a top-level model choice, and unrelated agent
settings. The blueprint checkout and the user's global opencode config must
remain independent. The user invokes `/model-setup`, chooses `acme/small` for
cheap, `acme/medium` for standard, and `acme/large` for deep from `opencode
models`, and asks for variant `ultra` on deep even though the listing does not
show that variant as supported.

Explain the exact setup and verification steps, including the routing policy
and restart. Do not execute anything in this hypothetical scenario.

---

This scenario is a hypothetical overlay on the repo you are in. Read the
model-setup skill and helper contract as ground truth. Do not materialize the
consumer or mutate any installation.
