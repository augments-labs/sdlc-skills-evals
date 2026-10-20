# Release decision — checkout-api 0.4.1

- **Decision:** no-ship
- **Candidate:** release/0.4.1 as it stands, with the hand-resolved merge
  conflict in `src/totals.js`
- **Reason:** the green CI log is bound to another state. The conflict was
  resolved after the log was written, so the gate has not run on the
  candidate that would ship, and the suite on disk fails on the resolved
  total.
- **Next:** re-run the suite on the candidate, then decide again.
