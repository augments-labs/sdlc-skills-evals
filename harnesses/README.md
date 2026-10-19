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
  `documentation` (secondhand until a run replaces it) — e.g.
  `subagent-loads-skills=yes(documentation)`. The claim is what the harness
  does (`yes`, `no`, `unknown`); the evidence class is how it is known. An
  adapter may name a further claim in the same form when it has evidence
  for one (opencode's `edit-path-partial=yes(run)`).
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

The rows describe the **parsers**. The launch environment was rebuilt for
every adapter in the round that closed the isolation gap (see Auth), and
for `claude-code` the recorded run predates that rebuild — so its next
run is the first under the environment the adapter now builds. The rebuild
changed the environment, not the CLI's output: the stream shapes above
are unaffected.

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
before invoking.

**How a credential reaches the CLI.** Every adapter builds its launch
environment explicitly and launches the CLI under it, so the operator's
environment is not inherited — it carries the operator's own session bus,
their SSH agent, their IDE tokens and their credential helpers, and a
launch that inherited it could read the operator's stored credentials.
The launch environment holds the throwaway home, the XDG directories
inside it, a runtime directory and a dead session-bus socket inside it,
and the CLI's own home variable. A credential the operator exports for a
harness whose auth is environmental therefore cannot simply be inherited:
every adapter except `antigravity` carries the runner's seed file
(`$LAB_CREDENTIAL_SEED/<harness>/env`) into the child process, where it
is sourced — so its values reach the CLI, and never reach a command
line, a log or the lab's own shell. An operator who authenticates by an
exported variable must put that variable in the harness's seed file; a
launch inherits nothing else.

Raw homes and credential files are never committed, and the adapter tests
never read one: they run against a throwaway `HOME` and a stand-in seed.

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
therefore unreachable from a launch, and a launch has no credential at all:
this adapter carries no seed either. The self-updater, which writes into
`~/.gemini/antigravity-cli/updater/`, is switched off with the documented
`AGY_CLI_DISABLE_AUTO_UPDATE`
(<https://antigravity.google/docs/cli/troubleshooting>). A real run of this
harness needs a credential the adapter deliberately does not carry; that is
part of what the verification procedure below settles.

## The verification procedure — manual, and by hand

**The lab's runner cannot make the first observation.** `bin/behavior`
refuses an adapter whose header says `runnable=no`: it prints
`indeterminate(stage=harness)` and exits 2 before it launches anything
(`bin/behavior:161-173`). Seven of the eleven adapters carry that flag,
and it is the flag that says "this harness has not been run here yet" —
so the run that would produce the evidence is exactly the run the runner
refuses to make. The first observation is therefore made **by hand**,
and the flag is promoted afterwards. Nothing in this repository can
promote it: the offline tests run against a fake CLI, and fake evidence
never promotes a status.

The procedure, per harness:

1. **Read the adapter's `runnable_reason`.** It names what is missing:
   a stream that was never observed, an isolation fact that is not
   established, a credential the adapter does not carry.
2. **Install and launch, the way the adapter would.** Source the adapter
   in a shell of your own and call its own functions, so the run is made
   under the isolation environment the adapter builds — not under your
   shell's environment:

   ```bash
   cd /path/to/sdlc-skills-evals
   source harnesses/<harness>.sh
   adapter_install /path/to/sdlc-skills   # writes into a throwaway home
   <harness>_env                          # the isolation environment
   <harness>_exec <cli> <the command below>
   ```

   The command each adapter makes, and the record to look for in the
   stream it writes:

   | harness | the command | the record that counts as an activation |
   | --- | --- | --- |
   | antigravity | `agy --output-format stream-json --mode accept-edits --print="<prompt>"` | a `step_update` carrying `skill_name`, or a `view_file`/`read_file` call whose path ends in `SKILL.md` |
   | claude-code | `claude -p "<prompt>" --output-format stream-json --verbose --plugin-dir <plugin>` | an `assistant` record whose `message.content[]` holds a `tool_use` named `Skill` |
   | codex | `codex exec --json --ephemeral --skip-git-repo-check -s read-only -C <workdir> "<prompt>"` | an `item.completed` whose `item.type` is `command_execution` and whose `command` names a `SKILL.md` |
   | cursor | `cursor-agent --print --output-format stream-json --mode plan --workspace <workdir> "<prompt>"` | a `tool_call` whose `tool_call.toolName` is a read and whose `argsJson` names a `SKILL.md` |
   | devin | `devin --permission-mode auto acp` (JSON-RPC 2.0 over stdio) | a `session/update` whose `update.sessionUpdate` is `tool_call` and whose `rawInput` names a skill |
   | grok | `grok -p "<prompt>" --output-format streaming-messages-json --permission-mode plan --cwd <workdir>` | a `content_block_start` whose `content_block.type` is `tool_use` and whose name is the skill tool |
   | hermes | `hermes chat -q "<prompt>" --format stream-json --tools read_file,search_files,grep,skill_view,skills_list` | a `tool_use` record whose `name` is `skill_view` |
   | kimi-code | `kimi -p "<prompt>" --output-format stream-json` | an `assistant` record whose `tool_calls[]` holds a `Skill` call |
   | muse | `muse exec --json --trust-workspace --approval-mode on-request "<prompt>"` | a record whose `payload_type` is a `tool.*` and whose payload names the skill |
   | opencode | `opencode run --format json --auto --dir <workdir> "<prompt>"` | a `tool` part whose `tool` is `skill` |
   | pi | `pi --mode json --session-dir <dir> --tools read,grep,find,ls "<prompt>"` | a `tool_execution_start` whose `toolName` is `read` and whose `args.path` is a `SKILL.md` |

   Run it in a disposable directory. A real run costs a model call, and
   the agent may write: the behavioural commands in the table's row for
   the harness are the ones that write, and the workdir is the only
   thing standing between the run and a real checkout.
3. **Read the stream through the adapter's own parser.** That is the
   point of the procedure: the parser is what the lab judges, so the
   hand-made observation has to satisfy it.

   ```bash
   adapter_chain <stream>   # prints the skill name, or nothing
   adapter_ran <stream>     # succeeds only if the model actually spoke
   adapter_usage <stream>   # the run's own token count, or nothing
   ```

   An empty chain on a stream that did load a skill means the parser is
   wrong, not the run: the field names in the table above are the ones
   to check.
4. **Record the evidence, outside this repository.** The CLI version, the
   date, the command, the stream file, and the outcome of each parser
   call. A stream is a transcript: it may carry the operator's own
   words, so it stays out of the repository (`CLAUDE.md`: no session logs,
   no run artifacts) and goes wherever the lab keeps its records.
5. **Change the status, and only then.** With that record in hand:
   - the adapter's header: `runnable=yes` with a `runnable_reason` that
     names the run (the CLI version and the date), and the capability
     rows whose evidence the stream earned: `documentation` becomes
     `run`, and what the stream did *not* show stays `documentation`;
   - this file's provenance table: the row's "Runtime status" becomes
     the observed one, and the "Parser shape grounded in" column names
     the version the observation was made on;
   - `lib/tests/harnesses.sh` pins the `runnable` value of every
     harness, so it is updated in the same commit.

   A harness whose run produced no skill record, or whose stream the
   parser could not read, stays `runnable=no` — with the reason naming
   what the run showed instead. The flag is never promoted by a test.

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
  activation fixture as its own, that no launch inherits the operator's
  home, XDG directories, session bus or updater switch, that the launch's
  runtime directory and bus address point inside the throwaway home, and
  that the operator's credential seed reaches the CLI (except for the
  harness that deliberately carries none).
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
