# Facebook feed review

Review-only CloudCart variant feed prototype. Only product 762 is enabled.

- No Meta import or store mutations.
- No CloudCart PAT or Meta token.
- `review/candidate.csv` is draft data with `review_required` on every row.
- `review/status.json` reports `ready_for_meta_import: false`.
- Refresh runs every six hours (UTC minute 17) and can be started manually.
- Source feeds are snapshots. Fetch time does not prove source generation time.
- GitHub scheduled workflows can be delayed or skipped.

The native CloudCart tracker uses parent product IDs. Candidate variant IDs are incompatible with a direct replacement of the existing advertising feed.

The converter has ten passing self-tests. Run `powershell -NoProfile -File ./cloudcart_variant_candidate.ps1 -SelfTest` on Windows or use `pwsh` on Linux.

## All-product inventory check

The same existing six-hour workflow also checks every Facebook feed product
against the native variant quantities, sizes, fb tags and effective prices.
It reuses the exact downloads used for the review candidate. It does not
filter or upload the production Meta feed.

`review/inventory-report.json` contains the latest successful input check,
available sizes/variants and exceptions. A run with valid inputs and detected
exceptions commits that report and then fails; malformed inputs fail without
replacing the previous report. Check the run status and report timestamp.

The scheduled report has `meta_snapshot_supplied: false`: no Meta API token is
used, so it does not prove Meta ingested the current feed. Source generation
age is unknown even when the download succeeds. No automatic >=2-size rule
is applied.

Only standard `ubuntu-latest` runners in this public repository are used.
Private copies are skipped. No second schedule, larger runner, artifact/cache
storage, paid dependency or external messaging is added.
