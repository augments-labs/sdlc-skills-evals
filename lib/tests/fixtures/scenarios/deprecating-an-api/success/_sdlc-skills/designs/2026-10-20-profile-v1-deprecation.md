# Deprecation record — profile-v1

- **Interface:** `GET /v1/profile`, the flattened profile response, in `src/routes.js`
- **Predecessor:** none
- **Owner:** the profiles API owner
- **Status:** `deprecated`
- **Decision ledger:** `.sdlc-skills/designs/2026-10-20-profile-v1-deprecation.ledger.md`, no row — the sunset date has not been set by its owner yet

## Interface

| Item | Value | Source |
| --- | --- | --- |
| Replacement | `src/profile-v2.js`, the nested profile shape | shipped in 2.3.0 |
| Old path calls the new one | no — the two shapes differ, and the old path keeps its own flattening | `src/profile.js:3` |
| Tests of the old path | `test/profile.test.js`, kept until the removal change | 2.3.0 |

## Callers

| Caller | Found by | Told how, when | Migrated |
| --- | --- | --- | --- |
| `src/client.js`, this repository | a search of the repository | the deprecation change, 2026-10-20 | no |
| clients outside this repository | not reachable — no caller count exists | not reachable | unknown |

## Use

| Read on | Period | Calls | Distinct callers | How counted |
| --- | --- | --- | --- | --- |
| 2026-10-20 | one release cycle | unknown | unknown | nothing counts it |

## Signal

- **Channel:** the `Deprecation` and `Sunset` response headers, and a `Link`
  with `rel="deprecation"` to the migration notes
- **Message:** the nested shape is the replacement; the sunset date is set by
  the interface's owner
- **Frequency:** once per response — the marker is a header, not a warning
- **Shipped in:** 2.3.1
- **Sunset date:** set by the interface's owner; this record carries no date
  yet, and no ledger row names one

## Removal

- **Brownout:** not run: the sunset date has not passed
- **Use at decision:** unknown — nothing counts it
- **Who breaks:** the callers outside this repository that nothing here can
  see; they recover by the nested shape
- **Decision:** hold until the owner sets the sunset date; no row yet
- **Removal shipped in:** not shipped

## Not measured

- Callers in other repositories, generated clients, and old app versions that
  never update: a repository search cannot see them, and nothing counts the
  old path.

## Next action

The interface's owner sets the sunset date, which is a ledger row beside this
record.
