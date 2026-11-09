# Facebook feed review

CloudCart feed checks and an isolated Meta Business Agent price feed.
The variant prototype below remains review-only and limited to product 762.

## AI-only price feed

`ai/catalog.xml` mirrors the public CloudCart Facebook RSS feed. Its only
changed item field is `custom_label_3`, which the Business Agent currently
uses as its free-text Price field. It contains the active EUR sale price
(with regular price) or the regular EUR price. Expired/future sales are not
described as current discounts. Parent product IDs, URLs, numeric price and
sale_price fields, availability, images and other labels are preserved.

The intended target is only catalog `903676082457339` (Facebook AI).
Advertising catalog `933781605022005` must keep the original CloudCart URL.
This is separate from the incompatible variant candidate files below.

One existing workflow now runs every two hours at UTC minute 17, before the
AI catalog's existing two-hour fetch at local minute 29. A push changing the
builder/tests/workflow also refreshes the output; generated commits do not
trigger another run. No second scheduled workflow or paid runner is added.

`ai/status.json` records build time and source/output hashes. Build time does
not prove source generation time. GitHub schedules can be delayed or skipped;
the feed is a periodic snapshot, not live stock. Invalid prices/currency,
duplicate IDs, invalid product links, empty sources or removal of more than
25% of previous IDs fail without replacing the last good feed. A large,
intentional removal requires a manually reviewed `--allow-large-change` run.
Monitor workflow failures and the status timestamp before relying on freshness.

The builder uses only the Python standard library, public product data and
the repository's existing standard public runner. No store or Meta token,
customer information, order action, customer test, or outgoing message is used.
The workflow itself makes no Meta or store mutations. Activation of the
generated URL in the AI catalog is a separate, verified rollout step.
The AI feed is now connected through existing feed `1037178389425923`.
Upload `1046045805205848` persisted all 158 items with zero errors, warnings
or deletions. Catalog readback confirmed 51 sale prices, no missing product
URLs and no numeric price/stock differences from the advertising catalog.

The review prototype and inventory report retain their own failure indicators.
A failed review-only product check does not prevent valid AI output from
being built from the already downloaded public Facebook source. An invalid
source or failed AI validation still prevents publication.

## Review-only variant prototype

- No Meta import or store mutations.
- No CloudCart PAT or Meta token.
- `review/candidate.csv` is draft data with `review_required` on every row.
- `review/status.json` reports `ready_for_meta_import: false`.
- Refresh shares the existing two-hour workflow and can be started manually.
- Source feeds are snapshots. Fetch time does not prove source generation time.
- GitHub scheduled workflows can be delayed or skipped.

The native CloudCart tracker uses parent product IDs. Candidate variant IDs are incompatible with a direct replacement of the existing advertising feed.

The converter has ten passing self-tests. Run `powershell -NoProfile -File ./cloudcart_variant_candidate.ps1 -SelfTest` on Windows or use `pwsh` on Linux.

## All-product inventory check

The same existing workflow also checks every Facebook feed product
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
