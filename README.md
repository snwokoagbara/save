# SAVE

SAVE is an iOS MVP for Kai, an AI-native assistant that helps users find HSA/FSA reimbursement and medical tax recovery money from receipts, email, and bank activity.

## Current V1 Prototype

- Assistant-native SwiftUI home screen.
- Demo onboarding with Gmail and bank source toggles.
- Receipt import through sample data, photo picker, and Vision OCR.
- Receipt review and line-item eligibility classification.
- Receipt metadata and line-item editing during review.
- HSA/FSA claim packet preparation and status tracking.
- Claim packet PDF export through the iOS share sheet.
- Schedule A medical-expense CSV/PDF export through the iOS share sheet.
- Local progress persistence with optional Supabase snapshot sync.
- Supabase first-class table sync for receipts, receipt line items, claim packets, and tax exports.
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

When those values are present in the Xcode scheme environment, the app shows a sign-in control in the top bar and account card. A successful sign-in stores the user session locally, syncs the current progress snapshot to `mvp_progress_snapshots`, and upserts V1 domain rows to `receipts`, `receipt_line_items`, `claim_packets`, and `tax_exports`.

Do not put `service_role`, secret keys, or hand-copied access tokens in iOS app configuration.

## V1 Next Steps

1. Restore from first-class Supabase tables once the table model has production data; keep `mvp_progress_snapshots` as the fallback until then.
2. Add claim-packet item join sync after claim packet rows are stable enough to avoid duplicate associations.
3. Add signed-in end-to-end QA for first-class table writes against the live Supabase project.
4. Enable Supabase leaked-password protection in the dashboard if the project plan supports it.
5. Defer Gmail OAuth and Plaid until receipt upload, review, claim packet export, tax export, and sync restore are solid.
