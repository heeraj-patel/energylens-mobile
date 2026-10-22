# Manual report PDF requirements

## Existing report path

Mobile creates an authenticated, owner-scoped Cloud preview for 1–25 selected appliances. Cloud stores an immutable snapshot for 24 hours and computes freshness on read. The preview has a SHA-256 digest. Email Report Now separately requires 1–5 valid recipients, explicit one-time approval of that digest, and confirmed provider acceptance. PDF use does not create a delivery request or change that email path.

Cloud's typed `reports.Preview` is the PDF source. Mobile's preview model intentionally displays a subset of v2 fields, so PDF rendering must not serialize that model. Cloud's existing fixed email HTML supplies the report's established prose and meaningful v2 estimate, measurement, recommendation, scope, and assumption content. Internal IDs, hashes, and source details that the established email copy does not expose remain in the stored snapshot; exposing additional customer copy requires owner review.

## Approved mobile flow and copy

On the existing saved report preview, show **View PDF** and **Save or share PDF** when the preview is current. Both request the exact saved preview digest. Show **Preparing PDF…** while downloading. On preparation failure show **Couldn’t prepare the PDF. Try again.** The in-app viewer uses **View PDF** as its title and offers **Save or share PDF**. Its built-in print and share actions are disabled. The system share chooser supplies its own native destination labels. Dismissing that chooser does not show a failure or a success claim.

Email recipients and approval are never required for PDF viewing or sharing. Existing email wording and behavior stay intact. A stale preview disables PDF actions; a 404, digest mismatch, expiry, or scope change cannot expose a PDF.

The open viewer listens for verified home scope changes and Cloud session generation changes. It hides and dismisses itself immediately on either loss, including the route that does not have an auxiliary lifecycle.

## API contract and security

`GET /v1/homes/{home}/reports/previews/{preview}/pdf` requires the existing owner bearer authentication and the `X-Report-Snapshot-SHA256` header containing the lower-case, 64-character digest shown in Mobile. Cloud calls the existing owner/home-scoped `Store.Get`, rejects stale/expired snapshots with `409 preview_stale`, and rejects digest mismatch with `409 snapshot_mismatch`. Missing/invalid digest is `400 invalid_request`; missing or cross-home preview is `404 not_found`; absent/invalid session is `401`. The successful response is `application/pdf`, `Content-Disposition: attachment; filename="energylens-report.pdf"`, and `Cache-Control: private, no-store`. The PDF is generated in memory and is not written to a Cloud report store. The endpoint neither sends email nor mutates a delivery request.

The PDF presents the established report's selected-appliance scope, date boundaries, fuel-aware units, estimates, measured summaries, recommendations, and assumptions from v1/v2. The canonical snapshot retains full source references and availability fields internally. The PDF omits recipients, account tokens, mutable delivery state, and unrelated household data. The renderer validates the stored digest before producing bytes. The mobile client also checks the PDF content type, signature, and bounded size before opening it.

## Acceptance evidence

- Cloud renderer tests cover a representative v2 snapshot with Unicode text, estimate and measurement units, recommendations, assumptions, and delivery-state exclusion.
- Cloud route tests cover authentication, cross-home denial, missing digest, mismatch, stale state, response headers and PDF signature, and absence of delivery enqueue.
- Mobile tests cover digest-bearing authenticated download, rejection of malformed responses, button state, progress and error wording, immediate viewer dismissal on sign-out, and continued email behavior.
- A local PDF sample should be inspected for multi-page wrapping and Unicode when a PDF renderer is available. Physical and simulator acceptance are deferred per the owner's instruction for this task; native chooser destinations and rasterization remain unverified on a device.

## Platform behavior and references

Mobile uses `printing`'s `PdfPreview` for an in-app view and `Printing.sharePdf` for the native share chooser. On iOS that chooser can expose Save to Files; Android targets depend on installed apps. The chooser does not guarantee a local save and its return value is not proof of completion. The plugin stages an OS-private temporary copy for sharing; its cleanup timing is platform-managed and is not asserted as immediate. Cloud uses `go-pdf/fpdf` with the repository's Source Sans 3 font and OFL license.

- [Flutter printing package and API](https://pub.dev/packages/printing)
- [go-pdf/fpdf documentation](https://github.com/go-pdf/fpdf/blob/main/doc/document.md)
- [Android document saving](https://developer.android.com/training/data-storage/shared/documents-files)
- [Android secure file sharing](https://developer.android.com/training/secure-file-sharing)
- [Apple Quick Look](https://developer.apple.com/documentation/quicklook/qlpreviewcontroller)
- [Apple sharing and document copies](https://developer.apple.com/documentation/uikit/collaborating-and-sharing-copies-of-your-data)
