# Adding a harness

One file, `harnesses/<name>.sh`, holding only what differs about that
CLI. Read `harnesses/README.md` for the contract, then:

1. Copy `harnesses/opencode.sh` (the primary, fully worked adapter) and
   delete every function the new CLI cannot honor — never stub one that
   pretends.
2. Implement the five required functions: `adapter_check` (CLI present),
   `adapter_install` (isolated home + plugin entry for the pinned
   source; empty source installs nothing), `adapter_chain` (structured
   skill-invocation records from the CLI's own stream — observed from a
   real stream, never assumed field names), `adapter_run_activation`
   (one bounded query), `adapter_run_behavioral` (full artifact run in
   a disposable workdir under a throwaway home).
3. Add what the CLI truly offers and nothing else: `adapter_usage` only
   from observed token keys (silence beats invention),
   `adapter_continue_behavioral` only from a structured session identity,
   `adapter_model` only for a real tier-to-model binding.
4. Write the header from observation: `runnable=no` with the reason
   until a real run on this machine proves otherwise;
   `permission_flags` naming exactly the flags the file passes (a header
   naming a flag the file does not pass fails `bin/check`);
   `capabilities` with `run` evidence only for what a real stream
   showed, `documentation` for the rest.
5. Keep the plugin's offline bindings in the plugin: install smoke,
   discovery, and inventory stay where they are; this file is the live
   half only.
6. Prove it: `lib/tests/harnesses.sh` for the contract, a parsing test
   against a real captured stream for `adapter_chain`, and one full
   activation seen through the CLI's own stream as acceptance. Seed
   `capabilities` from that run, replacing `documentation` labels with
   `run` where the stream earned it.
