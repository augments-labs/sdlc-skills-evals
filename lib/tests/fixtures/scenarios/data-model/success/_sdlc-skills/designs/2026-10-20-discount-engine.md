# Design — the discount engine

- **Status:** proposed
- **Approval rule:** the maintainer

## Concepts

- **Cart** — the order a discount is computed over. It has a line list, a
  subtotal, and a total.
- **Promotion** — a rule that discounts a cart. A promotion has a type, and
  the type decides whether two promotions stack.
- **Tier** — the volume band a cart falls into: under 100 units, 100 to 499
  units, and 500 units or more.

## Lifecycle

A promotion moves through three states, and only an active promotion applies:

| From | To | When |
| --- | --- | --- |
| draft | active | the promotion's window opens |
| active | expired | the promotion's window closes |
| draft | expired | the promotion is withdrawn before it opens |

A draft promotion never applies. An expired promotion never applies.

## Invariants

- A cart's total discount never exceeds the per-order cap.
- Only one exclusive promotion applies to a cart at a time.
- Stacking promotions never applies an exclusive promotion twice.
- A promotion's window is closed before it is expired.

## Relationships

- A cart has many lines and carries at most one tier.
- A promotion applies to many carts; a cart may carry many promotions.
- A cart's tier is derived from its line count, never stored separately.

## Stacking and exclusivity

A stacking promotion applies alongside every other promotion that applies to
the cart. An exclusive promotion applies alone: when one is present, no
stacking promotion applies and no second exclusive promotion applies.
