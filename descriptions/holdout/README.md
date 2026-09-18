# descriptions/holdout/

Fresh queries, written only **after** a description is selected — never used
to revise it. One file per skill that has one:
`holdout/<phase>/<skill>.json`, same entry shape as the set proper, every
entry carrying `"split": "holdout"`.

Run once, as the honest generalization check:

```bash
bin/triggering --harness opencode --skill yagni --split holdout
```

Then retire the queries into the set proper (re-split as train/validation
so the proportions hold) and delete the holdout file — a holdout that is
reused is a second validation set. `bin/check` enforces the convention:
5–10 entries, all `split: holdout`, none shared with the set.
