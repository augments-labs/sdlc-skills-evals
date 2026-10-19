# harnesses/

One launcher per agent CLI, holding **only what differs between them**: how
the plugin is installed, how the CLI is invoked, how an activation is
detected in its stream, and what a run cost. Each is sourced by a runner,
never executed directly, and none of them decides anything — judging an
observation belongs to the caller.

## The contract

Five required functions — `adapter_check`, `adapter_install`,
`adapter_chain`, `adapter_run_activation`, `adapter_run_behavioral` — plus
these optional ones, each only where the harness truly offers it:
`adapter_behavioral_events`, `adapter_continue_behavioral` (required only
for a scenario with follow-up turns; it must resume from structured session
evidence, never a fresh session), `adapter_model` and
`adapter_model_flags` (required only when a scenario sets
`scenario_model_tier` or a run passes `--tier`; the runner refuses the run
on an adapter without them rather than running the default model and
calling it that tier), `adapter_ran`, `adapter_usage`,
`adapter_activation_flags`, `adapter_prompt_suffix`, `adapter_name`.

Detection is structural, never a prose grep: an activation counts only
when the harness's own stream carries a structured skill-invocation
record. Each adapter's `adapter_chain` is written against a stream shape
that is NAMED in the file's header comment, with where that shape comes
from.

## Two evidence classes — and what each one buys

An adapter's parser is only as good as the evidence behind the field
names it reads. This lab keeps the two classes apart, because they buy
different things.

**Observed.** The shape was read out of a real stream this CLI produced on
a real machine. The parser is written against those field names, and the
label `run` in a capability header means exactly that.

**Documentation-grounded.** The shape comes from the CLI's own versioned
documentation or its own shipped source — a `--help` text, a `docs/`
page, a JSON schema compiled into the binary, a format the CLI's help
names as a published standard. No stream from this CLI has been observed
here, so the parser is exercised against a **labelled synthetic fixture**
under `lib/tests/fixtures/harnesses/<harness>/`. A synthetic fixture is
never presented as a real observation, and it never promotes `runnable`.

This refines the older rule that every parser already have an observed
stream. It does **not** relax the rule that a harness needs a real run
before it may be called `runnable=yes`: fake evidence never promotes
anything. Until the maintainer records a real run, every adapter that has
no observed stream carries `runnable=no` with the reason that says what is
missing.

## Headers

Every launcher carries four header fields:

- `runnable=yes|no` — verified on this machine, with `runnable_reason`.
  `no` is honest and permanent until a real run proves otherwise.
- `permission_flags` — exactly the permission-relevant flags the file
  passes (an empty value is forbidden; a file that passes none names the
  stream-shaping flag instead and says so). A header naming a flag the
  file does not pass fails `bin/check`.
- `capabilities` — `subagent-loads-skills`, `nesting-depth`,
  `tier-settable`, `session-start-event`, `post-compaction-event`, each as
  `claim(evidence)` with evidence `run` (observed from a real stream) or
  `documentation` (secondhand until a run replaces it).
- `adapter_name` — the harness's own name, which the runners print.

## Where each parser's shape comes from

`harnesses/README.md` is the capability and provenance table. Every row
names the source and its version, the fixture's provenance, and the
runtime status. A row whose runtime status is *unverified* is a parser
that has never seen this CLI's own stream.

| Harness | Stream format | Parser shape grounded in | Fixture provenance | Runtime status |
| --- | --- | --- | --- | --- |
| antigravity | `agy --output-format stream-json` (NDJSON) | the envelope observed on **agy 1.4.0**; the skill record's field names are the CLI's own `localagentcore.OutputEvent` tags (`skill_name`, `tool_name`) in the 1.4.0 binary; the isolation mechanism is the official CLI documentation (docs/install, docs/cli/troubleshooting), read 2026-10-20 | synthetic, mirroring the observed envelope | envelope observed; **skill record and isolation unverified** |
| claude-code | `claude -p --output-format stream-json` | **observed** on Claude Code 2.1.x (assistant `tool_use` records, terminal `result` usage) | synthetic, mirroring an observed stream | observed |
| codex | `codex exec --json` | **observed** on codex-cli 0.163.0 (`item.*` records, `turn.completed` usage) | synthetic, mirroring an observed stream | observed |
| cursor | `cursor-agent --print --output-format stream-json` | the emitter in **cursor-agent 2026.10.01's own shipped bundle** (`assistant`, `tool_call` with `tool_call.toolName` / `argsJson`) | synthetic | **unverified** |
| devin | `devin acp` (JSON-RPC 2.0, ACP v1) | the ACP v1 schema compiled into **devin 3000.11.3** (`agent_client_protocol_schema::v1`); the `sdlc-skills:` namespace from the pinned upstream's `tests/harnesses/devin.sh` | synthetic | **unverified** |
| grok | `grok -p --output-format streaming-messages-json` | the format **grok 1.0.62's own help** names: "NDJSON in the Anthropic Messages API wire format" | synthetic | **unverified** |
| hermes | `hermes chat -q --format stream-json` | **hermes 0.21.7's own source**, `hermes_cli/stream_json.py` (its module docstring states the protocol) | synthetic | **unverified** |
| kimi-code | `kimi -p --output-format stream-json` | **observed** on Kimi Code 2.x (`role`/`tool_calls` records) | synthetic, mirroring an observed stream | observed |
| muse | `muse exec --json` (JSONL) | the envelope **observed on muse 1.4.11-R6667.1** with `--provider echo`; the `tool.*` payload family from the 1.4.11 binary | synthetic, mirroring the observed envelope | envelope observed; **tool record unverified** |
| opencode | `opencode run --format json` | **observed** on opencode 1.x (`part.tool`, `part.state.input.name`, `step-finish` tokens) | synthetic, mirroring an observed stream | observed |
| pi | `pi --mode json` (JSONL) | **pi 1.3.0's own shipped docs**: `docs/json.md` (the event protocol), `docs/skills.md` (a skill is loaded by reading its `SKILL.md`) | synthetic | **unverified** |

The install facts of every row come from the pinned upstream's own
`tests/harnesses/*.sh` (upstream commit `638040d`, v11.0.0), which is the
reference for how each CLI loads and discovers a plugin.

## Globals the runners export

`plugin_dir` (the pinned plugin directory — adapters name the pin, never
the lab root), `harness_home`, `errlog`, `timeout_s`, `maxturns`,
`scenario_model_tier`. An unrunnable harness yields
`indeterminate(stage=harness)`, never `fail`.

## Auth

A run authenticates like the operator does. Where auth is a file
(Claude Code, Codex, Kimi, Devin), the adapter copies only that harness's
credential file into the isolated home. Where auth is environmental or
infrastructure-provided (OpenCode on this machine), no seed is needed;
where it is neither, the runner exports `$LAB_CREDENTIAL_SEED/<harness>/env`
before invoking. Raw homes and credential files are never committed, and
the adapter tests never read one: they run against a throwaway `HOME`.

**Antigravity is the odd one: its token is not a file.** The Antigravity CLI
authenticates from the operating system's secure keyring — on Linux the
secret service, reached over the D-Bus session bus ("the CLI attempts to
access your operating system's native secure keyring … If a valid token
profile is found, the CLI authenticates your session silently",
<https://antigravity.google/docs/install>, read 2026-10-20). That store
belongs to the operator's session, and no home redirect reaches it, so the
`antigravity` adapter launches the CLI with the session bus pointed at a
socket inside the throwaway home that nothing serves, and with
`XDG_RUNTIME_DIR` inside the throwaway home as well (where a secret-service
client looks for the bus when it is given no address). The operator's bus is
therefore unreachable from a launch, and a launch has no credential at all.
The self-updater, which writes into `~/.gemini/antigravity-cli/updater/`, is
switched off with the documented `AGY_CLI_DISABLE_AUTO_UPDATE`
(<https://antigravity.google/docs/cli/troubleshooting>). A real run of this
harness needs a credential the adapter deliberately does not carry; that is
part of what the verification procedure below settles.

## The adapter tests

- `lib/tests/harnesses.sh` — the contract: the adapter set equals the
  inventory exactly, every launcher defines the five required functions and
  the four header fields, every `permission_flags` value names a flag
  the file passes, and no launcher names a literal path to a CLI
  installation.
- `lib/tests/harness-adapters.sh` — the matrix: for every harness, a fake
  CLI on `PATH` proves the install, the none arm's isolation, the launch,
  the positive and negative activation, the malformed, empty, refused and
  unknown-format streams, the usage cases, the resume path and the tier
  path. It also proves that no harness's parser reads another harness's
  activation fixture as its own.
- `lib/tests/opencode-adapter.sh` — the opencode parser and the 1.x/2.x
  install layouts.

The fake CLI records every invocation, and the real CLIs are not on the
tests' `PATH`: an adapter that reaches one fails instead of launching it.
The matrix test proves that rather than assuming it — every agent CLI name
must resolve into the fake's own bin directory, the fake's log must show
that the binary which answered was the fake, and no other agent CLI may
appear in that log at all. The same log carries the environment each launch
was given, so the test can show that no home the CLI was handed points into
the operator's home, and that the Antigravity launch cannot reach the
operator's session bus.
