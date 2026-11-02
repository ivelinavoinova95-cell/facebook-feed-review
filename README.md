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
