# SAVE

SAVE is an iOS MVP for Kai, an AI-native assistant that helps users find HSA/FSA reimbursement and medical tax recovery money from receipts, email, and bank activity.

## Current V1 Prototype

- Assistant-native SwiftUI home screen.
- Demo onboarding with Gmail and bank source toggles.
- Receipt import through sample data, photo picker, and Vision OCR.
- Receipt review and line-item eligibility classification.
- Receipt metadata and line-item editing during review.
- HSA/FSA claim packet preparation and status tracking.
- Local administrator templates for HealthEquity, Inspira, WEX, and a generic guided-packet fallback.
- Claim packet PDF export through the iOS share sheet.
- Schedule A medical-expense CSV/PDF export through the iOS share sheet.
- Local progress persistence with optional Supabase snapshot sync and restore.
- Supabase first-class table sync/restore for receipts, receipt line items, claim packets, claim packet items, and tax exports.
- Account sync status, failure messaging, and manual sync retry.

## Build

Open `save.ai.xcodeproj` in Xcode, or build from this folder:

```sh
xcodebuild build-for-testing \
  -project save.ai.xcodeproj \
  -scheme save.ai \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/saveai-derived
```

## Test

The test bundle compiles with `build-for-testing`. Full simulator test execution can fail if CoreSimulator cannot launch the app runner; when that happens, retry from Xcode after booting a simulator.

```sh
xcodebuild test \
  -project save.ai.xcodeproj \
  -scheme save.ai \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
  -derivedDataPath /private/tmp/saveai-derived
```

## Supabase

Apply the schema draft in `supabase/save_v1_schema.sql` to a Supabase project. The schema enables RLS for user-owned rows, creates private storage buckets, and grants authenticated access to the V1 tables.

For local runs, copy `.env.example` to `.env` and fill in project values. The iOS app stays local-only unless the Supabase project values are present and a user session has been stored by the Auth client:

- `SAVE_SUPABASE_URL`
- `SAVE_SUPABASE_PUBLISHABLE_KEY`

When those values are present in the Xcode scheme environment, the app shows a sign-in control in the top bar and account card. A successful sign-in stores the user session locally, syncs the current progress snapshot to `mvp_progress_snapshots`, and upserts V1 domain rows to `receipts`, `receipt_line_items`, `claim_packets`, `claim_packet_items`, and `tax_exports`. On launch, the app restores from first-class domain tables first and falls back to `mvp_progress_snapshots` when domain rows are incomplete.

Do not put `service_role`, secret keys, or hand-copied access tokens in iOS app configuration.

## Verified QA

- June 14, 2026: Signed-in simulator QA against the live Supabase project synced 1 progress snapshot, 4 receipts, 7 receipt line items, 2 claim packets, and 1 tax export for the QA account.
- June 15, 2026: Signed-in simulator QA restored first-class Supabase rows, ignored stale claim packets with no joined items, and showed 3 claim packets in the app while the QA database still retained 4 historical claim packet rows and 3 claim packet item rows.

## V1 Next Steps

1. Enable Supabase leaked-password protection in the dashboard if the project plan supports it.
2. Move administrator templates from the local library into Supabase-managed rows when template editing/review workflow is needed.
3. Defer Gmail OAuth and Plaid until after the reviewed V1 prototype is accepted.
4. Decide whether to add a cleanup migration for historical QA-only claim packet rows with no `claim_packet_items`; the app now ignores them during restore.
