# SAVE

SAVE is an iOS MVP for Kai, an AI-native assistant that helps users find HSA/FSA reimbursement and medical tax recovery money from receipts, email, and bank activity.

## Current V1 Prototype

- Assistant-native SwiftUI home screen.
- Demo onboarding with Gmail and bank source toggles.
- Receipt import through sample data, photo picker, and Vision OCR.
- Receipt review and line-item eligibility classification.
- HSA/FSA claim packet preparation and status tracking.
- Schedule A medical-expense export preview.
- Local progress persistence with optional Supabase progress sync.

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

Do not put `service_role`, secret keys, or hand-copied access tokens in iOS app configuration.
