# SAVE

SAVE is an iOS MVP for Kai, an AI-native assistant that helps users find HSA/FSA reimbursement and medical tax recovery money from receipts and email evidence.

## Current V1 Prototype

- Assistant-native SwiftUI home screen.
- Demo onboarding with Gmail discovery and receipt-only paths.
- Receipt import through sample data, photo picker, and Vision OCR.
- Receipt review and line-item eligibility classification.
- Receipt metadata and line-item editing during review.
- HSA/FSA claim packet preparation, submission tracking, and reimbursement status tracking.
- Supabase-managed administrator templates for HealthEquity, Inspira, and WEX, with local defaults and a generic guided-packet fallback.
- Claim packet PDF export through the iOS share sheet.
- Schedule A medical-expense CSV/PDF export through the iOS share sheet.
- Local progress persistence with optional Supabase snapshot sync and restore.
- Supabase first-class table sync/restore for receipts, receipt line items, claim packets, claim packet items, and tax exports.
- Account sync status, failure messaging, and manual sync retry.

## Final Phase: Market Pain and Launch Premise

Research across HSA/FSA administrators and receipt-savings apps points to one strong launch opening: users are tired of fighting broken reimbursement workflows. The recurring pain is not just "saving money"; it is rejected receipts, unclear claim requirements, confusing portals, delayed or missing reimbursement, weak support, and low trust when apps say money has been found but do not help users recover it.

SAVE should launch V1 around this premise:

> Find hidden medical money without fighting broken HSA/FSA portals.

This keeps the campaign tied to what Kai can support today. Kai does not guarantee reimbursement or provide tax advice. Kai helps users find likely claimable expenses, prepare evidence-backed claim packets, track what was submitted, and export medical-expense records for tax review.

V1 maps directly to the market pain:

- Receipt OCR and receipt review reduce scan and rejection risk by letting users inspect the evidence before a claim is prepared.
- Claim packet generation reduces confusing HSA/FSA documentation work by turning eligible line items into administrator-ready evidence.
- Submission and reimbursement tracking reduce portal visibility gaps by recording method, confirmation number, notes, status, and reimbursed outcomes.
- Supabase-managed administrator templates reduce inconsistent administrator workflows by keeping HealthEquity, Inspira, and WEX requirements editable outside the app release cycle.
- CSV/PDF tax export supports year-end medical-expense recovery when users need itemized backup for a CPA or tax software.

Initial campaign assets:

- Landing page hero: "Find hidden medical money."
- Supporting line: "Kai scans your medical receipts, prepares HSA/FSA claim packets, and helps you track what is submitted and reimbursed."
- Founder-led post angle: "Your FSA/HSA admin should not make you forfeit your own money."
- Community outreach: FSA/HSA users, parents managing family medical receipts, and employees in benefits-heavy workplaces.
- Demo script: import receipt, review likely eligible amount, generate claim packet, mark submitted, track reimbursement.

Launch posture: founder-led and evidence-led first. Avoid paid ads and broad App Store launch until the reviewed prototype is accepted and the onboarding flow has enough proof that users can complete a real claim from receipt to submitted status.

## Gmail V1, Plaid V2

Gmail is now part of V1 because it is central to the "hidden medical money" promise. Gmail can surface pharmacy receipts, provider bills, order confirmations, administrator messages, and reimbursement evidence that users forgot to upload. Plaid moves to V2 because transaction matching is valuable but usually lacks line-item detail and carries heavier financial-linking complexity.

V1 Gmail implementation sequence:

1. Add Google OAuth for Gmail connection, using the narrowest viable Gmail read scope. The JWT-protected `gmail-oauth-start` and `gmail-oauth-callback` Edge Functions are deployed with PKCE support.
2. Store Gmail connection status in `source_connections` and keep refresh-token handling off-device. The table now supports provider subject, OAuth scopes, and non-secret provider metadata; refresh tokens are stored encrypted in `private.gmail_oauth_tokens`.
3. Check Gmail backend readiness before OAuth or import attempts. The JWT-protected `gmail-v1-preflight` Edge Function reports missing required secrets so the app can fail clearly instead of sending users into a broken Google flow.
4. Search Gmail for likely medical, pharmacy, dental, vision, HSA/FSA, and administrator receipt evidence. The JWT-protected `gmail-receipt-import` Edge Function is deployed for this scan.
5. Import found messages into the existing `receipts` review flow with source `gmail`; imported Gmail message IDs are tracked in `private.gmail_imported_messages` to avoid duplicates.
6. Let users review, correct, classify, generate claim packets, and track reimbursement from Gmail-sourced receipts.
7. Add disconnect/revoke UX, last-scanned status, and clear privacy copy explaining what Kai scans. The JWT-protected `gmail-disconnect` Edge Function is deployed and removes the stored Gmail token before marking the source revoked.

Before live Gmail testing, configure these Supabase Edge Function secrets:

- `GOOGLE_OAUTH_CLIENT_ID`
- `GMAIL_TOKEN_ENCRYPTION_KEY`
- `GOOGLE_OAUTH_CLIENT_SECRET` only if the selected Google OAuth client type requires it
- `GMAIL_OAUTH_SCOPES` optionally; if omitted, the function requests `https://www.googleapis.com/auth/gmail.readonly`
- `GMAIL_RECEIPT_QUERY` optionally to override the default medical/receipt search query
- `GMAIL_IMPORT_MAX_RESULTS` optionally to change the default import cap of 10 messages per scan

Public launch caveat: Google classifies broad Gmail read access such as `gmail.readonly` as a restricted scope. Prototype testing can start with test users, but public launch needs OAuth consent review and any required restricted-scope/security review before broad Gmail access is enabled.

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
- June 16, 2026: Simulator QA verified HealthEquity claim submission tracking from a ready packet through submitted state, including method, confirmation number, notes, and PDF submission-detail text.
- June 17, 2026: Build-for-testing verified Supabase-managed administrator template loading, local fallback merging, and managed claim packet document generation.
- June 17, 2026: Deployed the JWT-protected `gmail-oauth-start`, `gmail-oauth-callback`, and `gmail-receipt-import` Supabase Edge Functions, verified Gmail source-connection metadata columns, and created private encrypted Gmail token/import storage in the live project.
- June 17, 2026: Added Gmail V1 preflight checks so the app reports missing backend secrets before OAuth or Gmail import attempts.
- June 17, 2026: Added Gmail disconnect/privacy UX and deployed the JWT-protected `gmail-disconnect` Edge Function.

## V1 Next Steps

1. Enable Supabase leaked-password protection in the dashboard if the project plan supports it.
2. Configure Google OAuth and the required Edge Function secrets.
3. Validate `gmail-v1-preflight`, Gmail OAuth, and receipt import with a real test Google account.
4. Validate the hidden-medical-money premise with real Gmail-sourced receipts and completed claim packets.
5. Run the final founder-led marketing phase after Gmail-backed V1 is accepted.
6. Move Plaid bank matching to V2.
7. Decide whether to add a cleanup migration for historical QA-only claim packet rows with no `claim_packet_items`; the app now ignores them during restore.
