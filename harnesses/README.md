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
for a scenario with follow-up turns; it must resume from structured
session evidence, never a fresh session), `adapter_model` and
`adapter_model_flags` (required only when a scenario sets
`scenario_model_tier` or a run passes `--tier`; the runner refuses the run
on an adapter without them rather than running the default model and
calling it that tier), `adapter_ran`, `adapter_usage`,
`adapter_activation_flags`, `adapter_prompt_suffix`, `adapter_name`.

Detection is structural, never a prose grep: an activation counts only
when the harness's own stream carries a structured skill-invocation
record. Each adapter's `adapter_chain` is written against a stream
actually observed from the installed CLI, never against assumed field
names. Keys the parser relies on are named in the file's comments with
where they were observed.

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

## Globals the runners export

`plugin_dir` (the pinned plugin directory — adapters name the pin, never
the lab root), `harness_home`, `errlog`, `timeout_s`, `maxturns`,
`scenario_model_tier`. An unrunnable harness yields
`indeterminate(stage=harness)`, never `fail`.

## Auth

A run authenticates like the operator does. Where auth is a file
(Claude Code, Codex, Kimi), the adapter copies only that harness's
credential file into the isolated home. Where auth is environmental or
infrastructure-provided (OpenCode on this machine), no seed is needed;
where it is neither, the runner exports `$LAB_CREDENTIAL_SEED/<harness>/env`
before invoking. Raw homes and credential files are never committed.
