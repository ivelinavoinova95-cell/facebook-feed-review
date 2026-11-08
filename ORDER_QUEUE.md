# Manual CloudCart order queue

`read-order-queue.ps1` reads pending, non-archived, non-draft orders from the existing authenticated CloudCart CLI on the operator's Windows computer. It does not install software, change store data, send messages, or create a schedule. Do not add credentials or generated reports to this public repository.

Prerequisites: Windows PowerShell 5.1 or later, installed `cloudcart` CLI, and an existing authorized store session. Confirm the active store is the intended store before running. Keep the script on that computer and invoke it through Desktop Commander:

```powershell
.\read-order-queue.ps1 -Since '2026-10-09 00:00:00'
```

Choose the start date deliberately; the default is the original audit period. Dates use the store's date conventions. All order pages are read, with duplicate and cursor checks. The report is a sequence of reads, not an atomic snapshot.

The script prints a local report path under the Windows temporary directory. Reports include order IDs, creation dates, payment provider/status and carrier labels, but no customer names, email addresses, telephone numbers, street addresses or waybill numbers. Temporary files may be cleared by Windows; keep a report privately if required. Never commit reports, logs or CLI authentication files.

Categories:
- `packing_review`: pending orders marked not fulfilled; inspect stock and existing fulfillment before any dispatch.
- `shipping_payment_review`: fulfilled orders requiring delivery and payment review. Fulfilled is not proof of delivery or settlement.
- `payment_review`: at least one recorded failed payment; inspect the full payment state before action, as an order may have multiple attempts.
- `manual_review`: another fulfillment state requiring inspection.

`trackingQueriesSucceeded` means no tracking query threw an error. It does not guarantee carrier support, recent events, delivery or received payment. Inspect each `supported`, `trackingAvailable` and event date. Blank dates indicate unknown freshness; never mark an order Paid or completed from a label alone. Tracking failures remain visible in the report instead of silently dropping orders.

No scheduled execution is configured for this script. The existing GitHub inventory workflow is unchanged and does not run order queries. The code requires the existing local CloudCart access; no credentials are sent to GitHub Actions.

## Store and tracking coverage

Every CLI query explicitly targets `drehizavseki.com`, regardless of the CLI's active store. The report includes the store name. `trackingAvailable` is true only when all returned shipments are supported and carry a status label. `trackingNeedsReview` also flags missing carrier event dates, and `trackingReviewCount` totals affected orders. This is an inspection flag, not an assertion that the shipment is late or unpaid. Successful queries with missing data remain visible for review.

## Carrier exception signals

`carrierExceptionReview` flags any returned tracking label containing one of the observed Bulgarian phrases: `Предаване обратно на подател`, `Връщане към подателя`, or `Анулиране`. `carrierExceptionReviewCount` counts affected orders once. These are review signals; a cancelled or returning shipment is not proof that the whole order should be cancelled, refunded or restocked. An order may have replacement shipments. The script preserves the original order/payment categories and every returned carrier label. Unrecognized phrases remain visible; this is not an exhaustive carrier-status classifier. Match patterns use ASCII Unicode escapes to remain compatible with Windows PowerShell 5.1 source decoding.
