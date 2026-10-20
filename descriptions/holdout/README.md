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

## When this directory is written

It is written by the person who owns the selection, at one moment, and not
before: **after** a description has been selected for a skill, and **before**
any further revision of that description.

Nothing in this repository writes it, and no task in the successor plan
generates it. A holdout written before the selection is not a holdout: the
selection has already seen it, and the only honest number it can produce is
a second validation number wearing a test's name. So the directory stays
empty of query files until a real selection has happened on a real harness.

What the corpus in `descriptions/<phase>/<skill>.json` is, and is not:

- it is the **train** split, which a revision is allowed to be measured
  against and revised against;
- it is the **validation** split, which decides which revision is kept — and
  which is therefore burned by repeated selection;
- it is **not** the holdout. Neither split is an untouched test set, and no
  number produced from them is evidence that a description generalizes to
  openings nobody wrote down.

The step this directory reserves is therefore a **fresh holdout step**: pick
a skill, freeze its selected description, write 5–10 new openings that
nobody has tuned against, run them once, and record the result. The queries
are written by a person who has not seen the failures they would expose.
They are not derived from the existing set, not paraphrases of it, and not
written before the selection that the holdout is supposed to be untouched
by.

`bin/check` enforces the shape of a holdout file when one exists — 5–10
entries, all carrying `split: "holdout"`, and no query shared with the set
it belongs to — and it fails a **main** set that carries a `holdout` entry,
because that role belongs here and nowhere else. The gate does not and
cannot check that a holdout was written late; that is the author's record to
keep, and the corpus-audit row in `docs/upstream-coverage.md` is where a
selection would be cited.
