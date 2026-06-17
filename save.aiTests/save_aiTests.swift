//
//  save_aiTests.swift
//  save.aiTests
//
//  Created by Chris on 9/15/25.
//

import Foundation
import Testing
@testable import save_ai

struct save_aiTests {

    @Test func claimableEstimateIncludesOnlyEligibleMedicalRecovery() async throws {
        let summary = DemoData.claimSummary

        #expect(summary.totalClaimable == 734.18)
        #expect(summary.readyClaimCount == 3)
        #expect(summary.needsReviewCount == 1)
    }

    @Test func claimSummaryAssistantStatusLinePluralizesReviewItems() async throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let summary = ClaimSummary(receipts: [
            Receipt(
                merchant: "CVS",
                date: date,
                source: .gmail,
                lineItems: [
                    ReceiptLineItem(name: "Bandages", amount: 8.99, eligibility: .fsaEligible, confidence: 0.92),
                    ReceiptLineItem(name: "Unknown item", amount: 4.99, eligibility: .needsReview, confidence: 0.42)
                ]
            ),
            Receipt(
                merchant: "Walgreens",
                date: date,
                source: .bank,
                lineItems: [
                    ReceiptLineItem(name: "Sunscreen", amount: 18.77, eligibility: .fsaEligible, confidence: 0.95),
                    ReceiptLineItem(name: "Store item", amount: 3.50, eligibility: .needsReview, confidence: 0.39)
                ]
            ),
            Receipt(
                merchant: "LensCrafters",
                date: date,
                source: .camera,
                lineItems: [
                    ReceiptLineItem(name: "Prescription lenses", amount: 315.41, eligibility: .hsaEligible, confidence: 0.97),
                    ReceiptLineItem(name: "Case", amount: 6.25, eligibility: .needsReview, confidence: 0.44)
                ]
            )
        ])

        #expect(summary.assistantStatusLine == "3 claim packets found. 3 items need your review before Kai includes them.")
    }

    @Test func claimPacketRequiresEligibleLineItemsAndAdministrator() async throws {
        let readyPacket = ClaimPacket(
            administratorName: "HealthEquity",
            lineItems: DemoData.receipts.flatMap(\.lineItems).filter(\.isReimbursable),
            submissionMode: .guidedPacket
        )

        let blockedPacket = ClaimPacket(
            administratorName: "",
            lineItems: DemoData.receipts.flatMap(\.lineItems).filter { !$0.isReimbursable },
            submissionMode: .guidedPacket
        )

        #expect(readyPacket.isReadyForUserSubmission)
        #expect(!blockedPacket.isReadyForUserSubmission)
    }

    @Test func claimStatusOnlyAllowsForwardPrototypeTransitions() async throws {
        #expect(ClaimStatus.draft.canTransition(to: .ready))
        #expect(ClaimStatus.ready.canTransition(to: .submittedByUser))
        #expect(ClaimStatus.submittedByUser.canTransition(to: .reimbursed))
        #expect(!ClaimStatus.reimbursed.canTransition(to: .draft))
    }

    @Test func taxExportTotalsUseScheduleAAndReimbursableItems() async throws {
        let export = TaxExport(year: 2026, receipts: DemoData.receipts)

        #expect(export.totalMedicalExpenses == 934.18)
        #expect(export.csvRows.count == 4)
        #expect(export.csvPreview.contains("2026-05-17,Walgreens,FSA Sunscreen SPF 50,18.77,FSA eligible"))
    }

    @Test func mvpStartsWithConnectionTasksBeforeEstimateIsReady() async throws {
        let state = SaveMVPState()

        #expect(!state.isReadyForEstimate)
        #expect(state.activeTasks.map(\.title).contains("Connect Gmail"))
        #expect(state.activeTasks.map(\.title).contains("Link bank"))
    }

    @Test func mvpConnectsRequiredSourcesForFirstEstimate() async throws {
        var state = SaveMVPState()

        state.connect(.gmail)
        state.connect(.bank)

        #expect(state.isReadyForEstimate)
        #expect(!state.activeTasks.map(\.title).contains("Connect Gmail"))
        #expect(!state.activeTasks.map(\.title).contains("Link bank"))
    }

    @Test func mvpReviewActionExcludesUncertainLineItem() async throws {
        var state = SaveMVPState()

        #expect(state.summary.needsReviewCount == 1)

        state.excludeFirstReviewItem()

        #expect(state.summary.needsReviewCount == 0)
        #expect(!state.activeTasks.map(\.title).contains("Review Walgreens vitamin item"))
    }

    @Test func mvpPrepareClaimMovesDraftPacketToReady() async throws {
        var state = SaveMVPState()

        #expect(state.claimPackets.first?.status == .draft)

        state.prepareFirstDraftClaim()

        #expect(state.claimPackets.first?.status == .ready)
    }

    @Test func mvpSubmitClaimPacketMovesReadyPacketToSubmittedByUser() async throws {
        var state = SaveMVPState()

        state.prepareFirstDraftClaim()
        let packetID = try #require(state.claimPackets.first?.id)
        state.submitClaimPacket(packetID)

        #expect(state.claimPackets.first?.status == .submittedByUser)
    }

    @Test func mvpSubmitClaimPacketStoresSubmissionDetails() async throws {
        var state = SaveMVPState()
        let submittedAt = Date(timeIntervalSince1970: 1_800_002_400)
        let submission = ClaimSubmission(
            submittedAt: submittedAt,
            method: .administratorPortal,
            confirmationNumber: "HE-12345",
            notes: "Uploaded through HealthEquity portal."
        )

        state.prepareFirstDraftClaim()
        let packetID = try #require(state.claimPackets.first?.id)
        state.submitClaimPacket(packetID, submission: submission)

        #expect(state.claimPackets.first?.status == .submittedByUser)
        #expect(state.claimPackets.first?.submission == submission)
    }

    @Test func mvpMarkClaimReimbursedMovesSubmittedPacketToReimbursed() async throws {
        var state = SaveMVPState()

        state.prepareFirstDraftClaim()
        let packetID = try #require(state.claimPackets.first?.id)
        state.submitClaimPacket(packetID)
        state.markClaimReimbursed(packetID)

        #expect(state.claimPackets.first?.status == .reimbursed)
    }

    @Test func claimPacketDocumentIncludesAdministratorTotalAndLineItems() async throws {
        let packet = ClaimPacket(
            administratorName: "HealthEquity",
            lineItems: [
                ReceiptLineItem(name: "FSA Sunscreen SPF 50", amount: 18.77, eligibility: .fsaEligible, confidence: 0.96),
                ReceiptLineItem(name: "Prescription lenses", amount: 315.41, eligibility: .fsaEligible, confidence: 0.97)
            ],
            submissionMode: .guidedPacket,
            status: .ready
        )

        let document = ClaimPacketDocumentBuilder().build(from: packet)

        #expect(document.filename == "save-claim-health-equity.pdf")
        #expect(document.title == "HealthEquity claim packet")
        #expect(document.text.contains("Total claim amount: $334.18"))
        #expect(document.text.contains("FSA Sunscreen SPF 50 - $18.77 - FSA eligible"))
        #expect(document.text.contains("Prescription lenses - $315.41 - FSA eligible"))
    }

    @Test func claimPacketDocumentIncludesAdministratorTemplateInstructions() async throws {
        let packet = ClaimPacket(
            administratorName: "HealthEquity",
            lineItems: [
                ReceiptLineItem(name: "FSA Sunscreen SPF 50", amount: 18.77, eligibility: .fsaEligible, confidence: 0.96)
            ],
            submissionMode: .guidedPacket,
            status: .ready
        )

        let document = ClaimPacketDocumentBuilder().build(from: packet)

        #expect(document.template.version == "2026.1")
        #expect(document.text.contains("Template: HealthEquity 2026.1"))
        #expect(document.text.contains("- Account holder name"))
        #expect(document.text.contains("- Itemized receipt showing merchant, purchase date, eligible item, and amount"))
        #expect(document.text.contains("Submit through the HealthEquity member portal after reviewing the attached itemized evidence."))
    }

    @Test func claimPacketDocumentIncludesSubmissionChecklist() async throws {
        let packet = ClaimPacket(
            administratorName: "HealthEquity",
            lineItems: [
                ReceiptLineItem(name: "FSA Sunscreen SPF 50", amount: 18.77, eligibility: .fsaEligible, confidence: 0.96)
            ],
            submissionMode: .guidedPacket,
            status: .ready
        )

        let document = ClaimPacketDocumentBuilder().build(from: packet)

        #expect(document.template.submissionChecklist.contains("Review the required claim fields before opening the administrator portal."))
        #expect(document.text.contains("Submission checklist:"))
        #expect(document.text.contains("- Attach the generated SAVE claim packet PDF in HealthEquity."))
        #expect(document.text.contains("- Return to SAVE and mark the packet submitted after upload."))
    }

    @Test func claimPacketDocumentUsesManagedAdministratorTemplate() async throws {
        let packet = ClaimPacket(
            administratorName: "HealthEquity",
            lineItems: [
                ReceiptLineItem(name: "FSA Sunscreen SPF 50", amount: 18.77, eligibility: .fsaEligible, confidence: 0.96)
            ],
            submissionMode: .guidedPacket,
            status: .ready
        )
        let managedTemplate = ClaimAdministratorTemplate(
            administratorName: "HealthEquity",
            version: "managed-2026.2",
            supportedSubmissionMode: .guidedPacket,
            requiredFields: ["Member ID", "Service date", "Claim amount"],
            evidenceRequirements: ["Managed receipt rule"],
            submissionChecklist: ["Managed portal step"],
            instructions: ["Managed HealthEquity instruction."]
        )

        let document = ClaimPacketDocumentBuilder(templates: [managedTemplate]).build(from: packet)

        #expect(document.template.version == "managed-2026.2")
        #expect(document.text.contains("Template: HealthEquity managed-2026.2"))
        #expect(document.text.contains("- Member ID"))
        #expect(document.text.contains("- Managed portal step"))
        #expect(document.text.contains("Managed HealthEquity instruction."))
    }

    @Test func claimPacketDocumentIncludesSubmissionDetailsWhenSubmitted() async throws {
        let packet = ClaimPacket(
            administratorName: "HealthEquity",
            lineItems: [
                ReceiptLineItem(name: "FSA Sunscreen SPF 50", amount: 18.77, eligibility: .fsaEligible, confidence: 0.96)
            ],
            submissionMode: .guidedPacket,
            status: .submittedByUser,
            submission: ClaimSubmission(
                submittedAt: Date(timeIntervalSince1970: 1_800_002_400),
                method: .administratorPortal,
                confirmationNumber: "HE-12345",
                notes: "Uploaded through HealthEquity portal."
            )
        )

        let document = ClaimPacketDocumentBuilder().build(from: packet)

        #expect(document.text.contains("Submission details:"))
        #expect(document.text.contains("Method: Administrator portal"))
        #expect(document.text.contains("Confirmation: HE-12345"))
        #expect(document.text.contains("Notes: Uploaded through HealthEquity portal."))
    }

    @Test func administratorTemplateLibraryFallsBackToGenericGuidedPacket() async throws {
        let template = ClaimAdministratorTemplateLibrary.template(for: "Unknown Admin")

        #expect(template.administratorName == "Unknown Admin")
        #expect(template.version == "generic-2026.1")
        #expect(template.supportedSubmissionMode == .guidedPacket)
        #expect(template.requiredFields.contains("Claim amount"))
    }

    @Test func supabaseAdministratorTemplateLoaderBuildsManagedTemplates() async throws {
        let client = CapturingSupabaseAuthHTTPClient(
            responseData: """
            [
              {
                "administrator_name": "HealthEquity",
                "template_version": "2026.2",
                "supported_submission_mode": "guided_packet",
                "required_fields": ["Member ID", "Service date", "Claim amount"],
                "evidence_requirements": ["Managed receipt rule"],
                "submission_checklist": ["Managed portal step"],
                "instructions": ["Managed HealthEquity instruction."]
              }
            ]
            """.data(using: .utf8)!
        )
        let loader = SupabaseRESTClaimAdministratorTemplateLoader(
            configuration: SupabaseSaveMVPConfiguration(
                projectURL: URL(string: "https://example.supabase.co")!,
                publishableKey: "publishable-key"
            ),
            session: SupabaseAuthSession(
                userID: UUID(uuidString: "00000000-0000-0000-0000-000000000789")!,
                accessToken: "user-access-token",
                refreshToken: "refresh-token",
                expiresAt: Date(timeIntervalSince1970: 1_800_003_600)
            ),
            httpClient: client
        )

        let templates = try await loader.load()

        let request = try #require(client.requests.first)
        #expect(request.url?.absoluteString.contains("/rest/v1/administrator_templates?") == true)
        #expect(request.value(forHTTPHeaderField: "apikey") == "publishable-key")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer user-access-token")
        #expect(templates == [
            ClaimAdministratorTemplate(
                administratorName: "HealthEquity",
                version: "2026.2",
                supportedSubmissionMode: .guidedPacket,
                requiredFields: ["Member ID", "Service date", "Claim amount"],
                evidenceRequirements: ["Managed receipt rule"],
                submissionChecklist: ["Managed portal step"],
                instructions: ["Managed HealthEquity instruction."]
            )
        ])
    }

    @Test func mvpTaxExportCreatesArtifact() async throws {
        var state = SaveMVPState()

        #expect(state.taxReportArtifact == nil)

        state.exportTaxReport()

        #expect(state.taxReportArtifact?.filename == "save-medical-expenses-2026.csv")
        #expect(state.taxReportArtifact?.csvPreview.contains("date,merchant,item,amount,classification") == true)
    }

    @Test func taxExportDocumentIncludesCsvAndReportSummary() async throws {
        let export = TaxExport(year: 2026, receipts: DemoData.receipts)

        let document = TaxExportDocumentBuilder().build(from: export)

        #expect(document.csvFilename == "save-medical-expenses-2026.csv")
        #expect(document.pdfFilename == "save-medical-expenses-2026.pdf")
        #expect(document.title == "2026 Schedule A medical expense report")
        #expect(document.total == 934.18)
        #expect(document.csvText.contains("date,merchant,item,amount,classification"))
        #expect(document.reportText.contains("Total medical expenses: $934.18"))
        #expect(document.reportText.contains("Walgreens - FSA Sunscreen SPF 50 - $18.77 - FSA eligible"))
    }

    @Test func mvpProgressSnapshotRestoresCompletedActions() async throws {
        var state = SaveMVPState()

        state.completeOnboarding()
        state.connect(.gmail)
        state.connect(.bank)
        state.excludeFirstReviewItem()
        state.prepareFirstDraftClaim()
        state.exportTaxReport()

        let restored = SaveMVPState(persisted: state.persisted)

        #expect(restored.hasCompletedOnboarding)
        #expect(restored.isReadyForEstimate)
        #expect(restored.summary.needsReviewCount == 0)
        #expect(restored.claimPackets.first?.status == .ready)
        #expect(restored.taxReportArtifact?.filename == "save-medical-expenses-2026.csv")
    }

    @Test func mvpProgressSnapshotRestoresSubmittedClaimPackets() async throws {
        var state = SaveMVPState()

        state.prepareFirstDraftClaim()
        let packetID = try #require(state.claimPackets.first?.id)
        state.submitClaimPacket(packetID)

        let restored = SaveMVPState(persisted: state.persisted)

        #expect(restored.claimPackets.first?.status == .submittedByUser)
    }

    @Test func mvpProgressSnapshotRestoresClaimSubmissionDetails() async throws {
        var state = SaveMVPState()
        let submission = ClaimSubmission(
            submittedAt: Date(timeIntervalSince1970: 1_800_002_400),
            method: .administratorPortal,
            confirmationNumber: "HE-12345",
            notes: "Uploaded through HealthEquity portal."
        )

        state.prepareFirstDraftClaim()
        let packetID = try #require(state.claimPackets.first?.id)
        state.submitClaimPacket(packetID, submission: submission)

        let restored = SaveMVPState(persisted: state.persisted)

        #expect(restored.claimPackets.first?.submission == submission)
    }

    @Test func mvpProgressSnapshotRestoresReimbursedClaimPackets() async throws {
        var state = SaveMVPState()

        state.prepareFirstDraftClaim()
        let packetID = try #require(state.claimPackets.first?.id)
        state.submitClaimPacket(packetID)
        state.markClaimReimbursed(packetID)

        let restored = SaveMVPState(persisted: state.persisted)

        #expect(restored.claimPackets.first?.status == .reimbursed)
    }

    @Test func progressStoreRoundTripsSnapshot() async throws {
        let store = InMemorySaveMVPProgressStore()
        let snapshot = SaveMVPPersistedState(
            hasCompletedOnboarding: true,
            connectedSources: [.gmail],
            excludedFirstReviewItem: true,
            preparedFirstDraftClaim: false,
            exportedTaxReport: false
        )

        store.save(snapshot)

        #expect(store.load() == snapshot)
    }

    @Test func supabaseProgressRecordEncodesSnakeCaseUserFields() async throws {
        let snapshot = SaveMVPPersistedState(
            hasCompletedOnboarding: true,
            connectedSources: [.gmail, .bank],
            preparedFirstDraftClaim: true
        )
        let record = SupabaseSaveMVPProgressRecord(
            userID: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            state: snapshot,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let data = try JSONEncoder.saveMVP.encode(record)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"user_id\""))
        #expect(json.contains("\"updated_at\""))
        #expect(json.contains("\"hasCompletedOnboarding\""))
    }

    @Test func syncingProgressStoreSavesLocallyAndPushesSupabaseRecord() async throws {
        let localStore = InMemorySaveMVPProgressStore()
        let remoteSyncer = CapturingSaveMVPRemoteProgressSyncer()
        let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000456")!
        let updatedAt = Date(timeIntervalSince1970: 1_800_000_001)
        let store = SyncingSaveMVPProgressStore(
            localStore: localStore,
            remoteSyncer: remoteSyncer,
            userID: userID,
            now: { updatedAt }
        )
        let snapshot = SaveMVPPersistedState(hasCompletedOnboarding: true)

        store.save(snapshot)

        #expect(localStore.load() == snapshot)
        #expect(remoteSyncer.records == [
            SupabaseSaveMVPProgressRecord(
                userID: userID,
                state: snapshot,
                updatedAt: updatedAt
            )
        ])
    }

    @Test func syncingProgressStoreReportsRemoteSyncStatus() async throws {
        let localStore = InMemorySaveMVPProgressStore()
        let remoteSyncer = CapturingSaveMVPRemoteProgressSyncer()
        let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000456")!
        let updatedAt = Date(timeIntervalSince1970: 1_800_000_001)
        var statuses: [SaveMVPRemoteSyncStatus] = []
        let store = SyncingSaveMVPProgressStore(
            localStore: localStore,
            remoteSyncer: remoteSyncer,
            userID: userID,
            now: { updatedAt },
            remoteSyncStatusChanged: { statuses.append($0) }
        )

        store.save(SaveMVPPersistedState(hasCompletedOnboarding: true))

        #expect(statuses == [.syncing(updatedAt), .synced(updatedAt)])
    }

    @Test func syncingProgressStoreReportsRemoteSyncFailure() async throws {
        let localStore = InMemorySaveMVPProgressStore()
        let remoteSyncer = CapturingSaveMVPRemoteProgressSyncer()
        remoteSyncer.result = .failure(SupabaseProgressSyncError.httpStatus(500))
        let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000456")!
        let updatedAt = Date(timeIntervalSince1970: 1_800_000_001)
        var statuses: [SaveMVPRemoteSyncStatus] = []
        let store = SyncingSaveMVPProgressStore(
            localStore: localStore,
            remoteSyncer: remoteSyncer,
            userID: userID,
            now: { updatedAt },
            remoteSyncStatusChanged: { statuses.append($0) }
        )

        store.save(SaveMVPPersistedState(hasCompletedOnboarding: true))

        #expect(statuses == [.syncing(updatedAt), .failed(updatedAt)])
    }

    @Test func supabaseProgressSyncerBuildsAuthenticatedUpsertRequest() async throws {
        let client = CapturingSupabaseHTTPClient()
        let syncer = SupabaseRESTSaveMVPProgressSyncer(
            configuration: SupabaseSaveMVPConfiguration(
                projectURL: URL(string: "https://example.supabase.co")!,
                publishableKey: "publishable-key"
            ),
            session: SupabaseAuthSession(
                userID: UUID(uuidString: "00000000-0000-0000-0000-000000000789")!,
                accessToken: "user-access-token",
                refreshToken: "refresh-token",
                expiresAt: Date(timeIntervalSince1970: 1_800_003_600)
            ),
            httpClient: client
        )
        let snapshot = SaveMVPPersistedState(
            hasCompletedOnboarding: true,
            connectedSources: [.gmail, .bank]
        )

        syncer.push(
            SupabaseSaveMVPProgressRecord(
                userID: UUID(uuidString: "00000000-0000-0000-0000-000000000789")!,
                state: snapshot,
                updatedAt: Date(timeIntervalSince1970: 1_800_000_002)
            )
        ) { _ in }

        let request = try #require(client.requests.first)
        #expect(request.url?.absoluteString == "https://example.supabase.co/rest/v1/mvp_progress_snapshots")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "apikey") == "publishable-key")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer user-access-token")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Prefer") == "resolution=merge-duplicates")

        let body = try #require(request.httpBody)
        let json = try #require(String(data: body, encoding: .utf8))
        #expect(json.contains("\"user_id\""))
        #expect(json.contains("00000000-0000-0000-0000-000000000789"))
        #expect(json.contains("\"hasCompletedOnboarding\":true"))
    }

    @Test func supabaseFirstClassProgressSyncerBuildsDomainTableUpsertRequests() async throws {
        let client = CapturingSupabaseHTTPClient()
        let syncer = SupabaseRESTSaveMVPFirstClassProgressSyncer(
            configuration: SupabaseSaveMVPConfiguration(
                projectURL: URL(string: "https://example.supabase.co")!,
                publishableKey: "publishable-key"
            ),
            session: SupabaseAuthSession(
                userID: UUID(uuidString: "00000000-0000-0000-0000-000000000789")!,
                accessToken: "user-access-token",
                refreshToken: "refresh-token",
                expiresAt: Date(timeIntervalSince1970: 1_800_003_600)
            ),
            httpClient: client
        )
        var state = SaveMVPState()
        state.completeOnboarding()
        state.importReceiptDraft(
            ReceiptDraft(
                merchant: "CVS",
                purchasedAt: DemoData.date(year: 2026, month: 6, day: 10),
                totalAmount: 24.99,
                rawText: "CVS\n2026-06-10\nBandage roll 24.99\nTotal 24.99",
                lineItems: [
                    ReceiptDraftLineItem(name: "Bandage roll", amount: 24.99, confidence: 0.78)
                ]
            )
        )
        let importedItem = try #require(state.receipts.first?.lineItems.first)
        state.classifyLineItem(importedItem.id, as: .fsaEligible)
        state.prepareFirstDraftClaim()
        let packetID = try #require(state.claimPackets.first?.id)
        state.submitClaimPacket(
            packetID,
            submission: ClaimSubmission(
                submittedAt: Date(timeIntervalSince1970: 1_800_002_400),
                method: .administratorPortal,
                confirmationNumber: "HE-12345",
                notes: "Uploaded through HealthEquity portal."
            )
        )
        state.exportTaxReport()

        syncer.push(
            SupabaseSaveMVPProgressRecord(
                userID: UUID(uuidString: "00000000-0000-0000-0000-000000000789")!,
                state: state.persisted,
                updatedAt: Date(timeIntervalSince1970: 1_800_000_002)
            )
        ) { _ in }

        let urls = client.requests.compactMap { $0.url?.absoluteString }
        #expect(urls.contains("https://example.supabase.co/rest/v1/receipts"))
        #expect(urls.contains("https://example.supabase.co/rest/v1/receipt_line_items"))
        #expect(urls.contains("https://example.supabase.co/rest/v1/claim_packets"))
        #expect(urls.contains("https://example.supabase.co/rest/v1/claim_packet_items"))
        #expect(urls.contains("https://example.supabase.co/rest/v1/tax_exports"))
        #expect(client.requests.allSatisfy { $0.value(forHTTPHeaderField: "Prefer") == "resolution=merge-duplicates" })

        let receiptRequest = try #require(client.requests.first { $0.url?.lastPathComponent == "receipts" })
        let receiptData = try #require(receiptRequest.httpBody)
        let receiptBody = try #require(String(data: receiptData, encoding: .utf8))
        #expect(receiptBody.contains("\"merchant\":\"CVS\""))
        #expect(receiptBody.contains("\"status\":\"classified\""))

        let lineItemRequest = try #require(client.requests.first { $0.url?.lastPathComponent == "receipt_line_items" })
        let lineItemData = try #require(lineItemRequest.httpBody)
        let lineItemBody = try #require(String(data: lineItemData, encoding: .utf8))
        #expect(lineItemBody.contains("\"normalized_name\":\"Bandage roll\""))
        #expect(lineItemBody.contains("\"eligibility\":\"fsa_eligible\""))

        let claimPacketRequest = try #require(client.requests.first { $0.url?.lastPathComponent == "claim_packets" })
        let claimPacketData = try #require(claimPacketRequest.httpBody)
        let claimPacketBody = try #require(String(data: claimPacketData, encoding: .utf8))
        #expect(claimPacketBody.contains("\"template_version\":\"2026.1\""))
        #expect(claimPacketBody.contains("\"submitted_at\":\"2027-01-15T08:40:00Z\""))
        #expect(claimPacketBody.contains("\"submission_method\":\"administrator_portal\""))
        #expect(claimPacketBody.contains("\"submission_confirmation_number\":\"HE-12345\""))
        #expect(claimPacketBody.contains("\"submission_note\":\"Uploaded through HealthEquity portal.\""))
    }

    @Test func supabaseFirstClassProgressSyncerBuildsClaimPacketItemRows() async throws {
        let client = CapturingSupabaseHTTPClient()
        let syncer = SupabaseRESTSaveMVPFirstClassProgressSyncer(
            configuration: SupabaseSaveMVPConfiguration(
                projectURL: URL(string: "https://example.supabase.co")!,
                publishableKey: "publishable-key"
            ),
            session: SupabaseAuthSession(
                userID: UUID(uuidString: "00000000-0000-0000-0000-000000000789")!,
                accessToken: "user-access-token",
                refreshToken: "refresh-token",
                expiresAt: Date(timeIntervalSince1970: 1_800_003_600)
            ),
            httpClient: client
        )
        var state = SaveMVPState()
        state.prepareFirstDraftClaim()

        syncer.push(
            SupabaseSaveMVPProgressRecord(
                userID: UUID(uuidString: "00000000-0000-0000-0000-000000000789")!,
                state: state.persisted,
                updatedAt: Date(timeIntervalSince1970: 1_800_000_002)
            )
        ) { _ in }

        let itemRequest = try #require(client.requests.first { $0.url?.lastPathComponent == "claim_packet_items" })
        let itemData = try #require(itemRequest.httpBody)
        let itemBody = try #require(String(data: itemData, encoding: .utf8))
        #expect(itemBody.contains("\"user_id\":\"00000000-0000-0000-0000-000000000789\""))
        #expect(itemBody.contains("\"claim_packet_id\""))
        #expect(itemBody.contains("\"receipt_line_item_id\""))
    }

    @Test func supabaseFirstClassProgressSyncerKeepsClaimPacketIDStableAcrossStatusChanges() async throws {
        let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000789")!
        let client = CapturingSupabaseHTTPClient()
        let syncer = SupabaseRESTSaveMVPFirstClassProgressSyncer(
            configuration: SupabaseSaveMVPConfiguration(
                projectURL: URL(string: "https://example.supabase.co")!,
                publishableKey: "publishable-key"
            ),
            session: SupabaseAuthSession(
                userID: userID,
                accessToken: "user-access-token",
                refreshToken: "refresh-token",
                expiresAt: Date(timeIntervalSince1970: 1_800_003_600)
            ),
            httpClient: client
        )
        var readyState = SaveMVPState()
        readyState.prepareFirstDraftClaim()
        var submittedState = readyState
        let packetID = try #require(submittedState.claimPackets.first?.id)
        submittedState.submitClaimPacket(packetID)

        syncer.push(
            SupabaseSaveMVPProgressRecord(
                userID: userID,
                state: readyState.persisted,
                updatedAt: Date(timeIntervalSince1970: 1_800_000_002)
            )
        ) { _ in }
        syncer.push(
            SupabaseSaveMVPProgressRecord(
                userID: userID,
                state: submittedState.persisted,
                updatedAt: Date(timeIntervalSince1970: 1_800_000_003)
            )
        ) { _ in }

        let claimPacketRequests = client.requests.filter { $0.url?.lastPathComponent == "claim_packets" }
        let firstRequest = try #require(claimPacketRequests.first)
        let secondRequest = try #require(claimPacketRequests.last)
        let firstID = try #require(try firstRequest.firstJSONArrayObjectStringValue(forKey: "id"))
        let secondID = try #require(try secondRequest.firstJSONArrayObjectStringValue(forKey: "id"))
        #expect(firstID == secondID)
    }

    @Test func supabaseFirstClassProgressSyncerWaitsForReceiptsBeforeLineItems() async throws {
        let client = DeferredSupabaseHTTPClient()
        let syncer = SupabaseRESTSaveMVPFirstClassProgressSyncer(
            configuration: SupabaseSaveMVPConfiguration(
                projectURL: URL(string: "https://example.supabase.co")!,
                publishableKey: "publishable-key"
            ),
            session: SupabaseAuthSession(
                userID: UUID(uuidString: "00000000-0000-0000-0000-000000000789")!,
                accessToken: "user-access-token",
                refreshToken: "refresh-token",
                expiresAt: Date(timeIntervalSince1970: 1_800_003_600)
            ),
            httpClient: client
        )

        syncer.push(
            SupabaseSaveMVPProgressRecord(
                userID: UUID(uuidString: "00000000-0000-0000-0000-000000000789")!,
                state: SaveMVPState().persisted,
                updatedAt: Date(timeIntervalSince1970: 1_800_000_002)
            )
        ) { _ in }

        #expect(client.requestedTables == ["receipts"])

        client.completeNext()
        #expect(client.requestedTables == ["receipts", "receipt_line_items"])

        client.completeNext()
        #expect(client.requestedTables == ["receipts", "receipt_line_items", "claim_packets"])

        client.completeNext()
        #expect(client.requestedTables == ["receipts", "receipt_line_items", "claim_packets", "claim_packet_items"])

        client.completeNext()
        #expect(client.requestedTables == ["receipts", "receipt_line_items", "claim_packets", "claim_packet_items", "tax_exports"])
    }

    @Test func supabaseProgressLoaderBuildsAuthenticatedSnapshotRequestAndDecodesState() async throws {
        let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000789")!
        let client = CapturingSupabaseAuthHTTPClient(
            responseData: """
            [
              {
                "state": {
                  "hasCompletedOnboarding": true,
                  "connectedSources": ["gmail", "bank"],
                  "preparedFirstDraftClaim": true
                }
              }
            ]
            """.data(using: .utf8)!
        )
        let loader = SupabaseRESTSaveMVPProgressLoader(
            configuration: SupabaseSaveMVPConfiguration(
                projectURL: URL(string: "https://example.supabase.co")!,
                publishableKey: "publishable-key"
            ),
            session: SupabaseAuthSession(
                userID: userID,
                accessToken: "user-access-token",
                refreshToken: "refresh-token",
                expiresAt: Date(timeIntervalSince1970: 1_800_003_600)
            ),
            httpClient: client
        )

        let snapshot = try await loader.load()

        let request = try #require(client.requests.first)
        #expect(request.url?.absoluteString == "https://example.supabase.co/rest/v1/mvp_progress_snapshots?select=state&user_id=eq.00000000-0000-0000-0000-000000000789&limit=1")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "apikey") == "publishable-key")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer user-access-token")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(snapshot == SaveMVPPersistedState(
            hasCompletedOnboarding: true,
            connectedSources: [.gmail, .bank],
            preparedFirstDraftClaim: true
        ))
    }

    @Test func supabaseProgressLoaderReturnsNilWhenNoSnapshotExists() async throws {
        let client = CapturingSupabaseAuthHTTPClient(responseData: "[]".data(using: .utf8)!)
        let loader = SupabaseRESTSaveMVPProgressLoader(
            configuration: SupabaseSaveMVPConfiguration(
                projectURL: URL(string: "https://example.supabase.co")!,
                publishableKey: "publishable-key"
            ),
            session: SupabaseAuthSession(
                userID: UUID(uuidString: "00000000-0000-0000-0000-000000000789")!,
                accessToken: "user-access-token",
                refreshToken: "refresh-token",
                expiresAt: Date(timeIntervalSince1970: 1_800_003_600)
            ),
            httpClient: client
        )

        let snapshot = try await loader.load()

        #expect(snapshot == nil)
    }

    @Test func supabaseFirstClassProgressLoaderBuildsPersistedStateFromDomainRows() async throws {
        let receiptID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let lineItemID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        let claimPacketID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
        let client = QueueingSupabaseAuthHTTPClient(responseData: [
            """
            [
              {
                "id": "\(receiptID.uuidString)",
                "source": "gmail",
                "status": "classified",
                "merchant": "CVS Health",
                "purchased_at": "2026-06-10",
                "total_amount": 8.99
              }
            ]
            """.data(using: .utf8)!,
            """
            [
              {
                "id": "\(lineItemID.uuidString)",
                "receipt_id": "\(receiptID.uuidString)",
                "original_text": "Bandages",
                "normalized_name": "Flexible bandages",
                "amount": 8.99,
                "eligibility": "fsa_eligible",
                "confidence": 0.91
              }
            ]
            """.data(using: .utf8)!,
            """
            [
              {
                "id": "\(claimPacketID.uuidString)",
                "administrator_name": "HealthEquity",
                "status": "submitted_by_user",
                "submission_mode": "guided_packet",
                "claim_amount": 8.99,
                "submitted_at": "2027-01-15T08:40:00Z",
                "submission_method": "administrator_portal",
                "submission_confirmation_number": "HE-12345",
                "submission_note": "Uploaded through HealthEquity portal."
              }
            ]
            """.data(using: .utf8)!,
            """
            [
              {
                "claim_packet_id": "\(claimPacketID.uuidString)",
                "receipt_line_item_id": "\(lineItemID.uuidString)"
              }
            ]
            """.data(using: .utf8)!,
            """
            [
              {
                "tax_year": 2026,
                "status": "generated",
                "total_medical_expenses": 8.99,
                "generated_at": "2026-06-14T20:00:00Z"
              }
            ]
            """.data(using: .utf8)!
        ])
        let loader = SupabaseRESTSaveMVPFirstClassProgressLoader(
            configuration: SupabaseSaveMVPConfiguration(
                projectURL: URL(string: "https://example.supabase.co")!,
                publishableKey: "publishable-key"
            ),
            session: SupabaseAuthSession(
                userID: UUID(uuidString: "00000000-0000-0000-0000-000000000789")!,
                accessToken: "user-access-token",
                refreshToken: "refresh-token",
                expiresAt: Date(timeIntervalSince1970: 1_800_003_600)
            ),
            httpClient: client
        )

        let persisted = try #require(try await loader.load())
        let state = SaveMVPState(persisted: persisted)

        #expect(client.requestedTables == ["receipts", "receipt_line_items", "claim_packets", "claim_packet_items", "tax_exports"])
        #expect(state.hasCompletedOnboarding)
        #expect(state.connectedSources == Set([ConnectedSource.gmail]))
        #expect(state.receipts.first?.merchant == "CVS Health")
        #expect(state.receipts.first?.lineItems.first?.id == lineItemID)
        #expect(state.receipts.first?.lineItems.first?.eligibility == .fsaEligible)
        #expect(state.claimPackets.first?.id == claimPacketID)
        #expect(state.claimPackets.first?.lineItems.first?.id == lineItemID)
        let submission = try #require(state.claimPackets.first?.submission)
        #expect(submission.submittedAt == Date(timeIntervalSince1970: 1_800_002_400))
        #expect(submission.method == .administratorPortal)
        #expect(submission.confirmationNumber == "HE-12345")
        #expect(submission.notes == "Uploaded through HealthEquity portal.")
        #expect(state.taxReportArtifact?.total == 8.99)
    }

    @Test func supabaseFirstClassProgressLoaderSkipsClaimPacketsWithoutItems() async throws {
        let receiptID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let lineItemID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        let currentPacketID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
        let stalePacketID = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!
        let client = QueueingSupabaseAuthHTTPClient(responseData: [
            """
            [
              {
                "id": "\(receiptID.uuidString)",
                "source": "gmail",
                "status": "classified",
                "merchant": "CVS Health",
                "purchased_at": "2026-06-10",
                "total_amount": 8.99
              }
            ]
            """.data(using: .utf8)!,
            """
            [
              {
                "id": "\(lineItemID.uuidString)",
                "receipt_id": "\(receiptID.uuidString)",
                "original_text": "Bandages",
                "normalized_name": "Flexible bandages",
                "amount": 8.99,
                "eligibility": "fsa_eligible",
                "confidence": 0.91
              }
            ]
            """.data(using: .utf8)!,
            """
            [
              {
                "id": "\(stalePacketID.uuidString)",
                "administrator_name": "HealthEquity",
                "status": "ready",
                "submission_mode": "guided_packet",
                "claim_amount": 8.99
              },
              {
                "id": "\(currentPacketID.uuidString)",
                "administrator_name": "HealthEquity",
                "status": "ready",
                "submission_mode": "guided_packet",
                "claim_amount": 8.99
              }
            ]
            """.data(using: .utf8)!,
            """
            [
              {
                "claim_packet_id": "\(currentPacketID.uuidString)",
                "receipt_line_item_id": "\(lineItemID.uuidString)"
              }
            ]
            """.data(using: .utf8)!,
            "[]".data(using: .utf8)!
        ])
        let loader = SupabaseRESTSaveMVPFirstClassProgressLoader(
            configuration: SupabaseSaveMVPConfiguration(
                projectURL: URL(string: "https://example.supabase.co")!,
                publishableKey: "publishable-key"
            ),
            session: SupabaseAuthSession(
                userID: UUID(uuidString: "00000000-0000-0000-0000-000000000789")!,
                accessToken: "user-access-token",
                refreshToken: "refresh-token",
                expiresAt: Date(timeIntervalSince1970: 1_800_003_600)
            ),
            httpClient: client
        )

        let persisted = try #require(try await loader.load())
        let state = SaveMVPState(persisted: persisted)

        #expect(state.claimPackets.map(\.id) == [currentPacketID])
        #expect(state.claimPackets.first?.lineItems.map(\.id) == [lineItemID])
    }

    @Test func fallbackProgressLoaderUsesSnapshotWhenFirstClassRowsAreIncomplete() async throws {
        let snapshot = SaveMVPPersistedState(hasCompletedOnboarding: true, connectedSources: [.bank])
        let loader = FallbackSaveMVPRemoteProgressLoader(
            primary: StubRemoteProgressLoader(snapshot: nil),
            fallback: StubRemoteProgressLoader(snapshot: snapshot)
        )

        let restored = try await loader.load()

        #expect(restored == snapshot)
    }

    @Test func supabasePasswordAuthClientBuildsTokenRequestAndDecodesSession() async throws {
        let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000abc")!
        let client = CapturingSupabaseAuthHTTPClient(
            responseData: """
            {
              "access_token": "access-token",
              "refresh_token": "refresh-token",
              "expires_in": 3600,
              "user": { "id": "\(userID.uuidString)" }
            }
            """.data(using: .utf8)!
        )
        let authClient = SupabaseRESTAuthClient(
            configuration: SupabaseSaveMVPConfiguration(
                projectURL: URL(string: "https://example.supabase.co")!,
                publishableKey: "publishable-key"
            ),
            httpClient: client,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        let session = try await authClient.signIn(email: "kai@example.com", password: "correct-password")

        let request = try #require(client.requests.first)
        #expect(request.url?.absoluteString == "https://example.supabase.co/auth/v1/token?grant_type=password")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "apikey") == "publishable-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(request.httpBody)
        let json = try #require(String(data: body, encoding: .utf8))
        #expect(json.contains("\"email\":\"kai@example.com\""))
        #expect(json.contains("\"password\":\"correct-password\""))
        #expect(session == SupabaseAuthSession(
            userID: userID,
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1_800_003_600)
        ))
    }

    @Test func supabasePasswordAuthClientRefreshesSessionWithRefreshToken() async throws {
        let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000abc")!
        let client = CapturingSupabaseAuthHTTPClient(
            responseData: """
            {
              "access_token": "new-access-token",
              "refresh_token": "new-refresh-token",
              "expires_in": 3600,
              "user": { "id": "\(userID.uuidString)" }
            }
            """.data(using: .utf8)!
        )
        let authClient = SupabaseRESTAuthClient(
            configuration: SupabaseSaveMVPConfiguration(
                projectURL: URL(string: "https://example.supabase.co")!,
                publishableKey: "publishable-key"
            ),
            httpClient: client,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        let session = try await authClient.refreshSession(refreshToken: "old-refresh-token")

        let request = try #require(client.requests.first)
        #expect(request.url?.absoluteString == "https://example.supabase.co/auth/v1/token?grant_type=refresh_token")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "apikey") == "publishable-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(request.httpBody)
        let json = try #require(String(data: body, encoding: .utf8))
        #expect(json.contains("\"refresh_token\":\"old-refresh-token\""))
        #expect(session == SupabaseAuthSession(
            userID: userID,
            accessToken: "new-access-token",
            refreshToken: "new-refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1_800_003_600)
        ))
    }

    @Test func supabasePasswordAuthClientBuildsSignupRequestAndDecodesPendingUser() async throws {
        let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000aaa")!
        let client = CapturingSupabaseAuthHTTPClient(
            responseData: """
            {
              "id": "\(userID.uuidString)",
              "email": "kai@example.com"
            }
            """.data(using: .utf8)!
        )
        let authClient = SupabaseRESTAuthClient(
            configuration: SupabaseSaveMVPConfiguration(
                projectURL: URL(string: "https://example.supabase.co")!,
                publishableKey: "publishable-key"
            ),
            httpClient: client
        )

        let result = try await authClient.signUp(email: "kai@example.com", password: "new-password")

        let request = try #require(client.requests.first)
        #expect(request.url?.absoluteString == "https://example.supabase.co/auth/v1/signup")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "apikey") == "publishable-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(request.httpBody)
        let json = try #require(String(data: body, encoding: .utf8))
        #expect(json.contains("\"email\":\"kai@example.com\""))
        #expect(json.contains("\"password\":\"new-password\""))
        #expect(result == SupabaseAuthSignUpResult(userID: userID, session: nil))
    }

    @Test func supabasePasswordAuthClientStoresSignupSessionWhenReturned() async throws {
        let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000bbb")!
        let client = CapturingSupabaseAuthHTTPClient(
            responseData: """
            {
              "access_token": "signup-access-token",
              "refresh_token": "signup-refresh-token",
              "expires_in": 3600,
              "user": { "id": "\(userID.uuidString)" }
            }
            """.data(using: .utf8)!
        )
        let authClient = SupabaseRESTAuthClient(
            configuration: SupabaseSaveMVPConfiguration(
                projectURL: URL(string: "https://example.supabase.co")!,
                publishableKey: "publishable-key"
            ),
            httpClient: client,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        let result = try await authClient.signUp(email: "kai@example.com", password: "new-password")

        #expect(result == SupabaseAuthSignUpResult(
            userID: userID,
            session: SupabaseAuthSession(
                userID: userID,
                accessToken: "signup-access-token",
                refreshToken: "signup-refresh-token",
                expiresAt: Date(timeIntervalSince1970: 1_800_003_600)
            )
        ))
    }

    @Test func authSessionStoreRoundTripsSession() async throws {
        let store = InMemorySupabaseAuthSessionStore()
        let session = SupabaseAuthSession(
            userID: UUID(uuidString: "00000000-0000-0000-0000-000000000def")!,
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1_800_003_600)
        )

        store.save(session)

        #expect(store.load() == session)
    }

    @Test func signInControllerStoresReturnedSession() async throws {
        let session = SupabaseAuthSession(
            userID: UUID(uuidString: "00000000-0000-0000-0000-000000000111")!,
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1_800_003_600)
        )
        let authClient = CapturingAuthSigningIn(session: session)
        let sessionStore = InMemorySupabaseAuthSessionStore()
        let controller = SaveMVPSignInController(
            authClient: authClient,
            sessionStore: sessionStore
        )

        let signedInSession = try await controller.signIn(
            email: "kai@example.com",
            password: "correct-password"
        )

        #expect(signedInSession == session)
        #expect(sessionStore.load() == session)
        #expect(authClient.requests == [
            CapturingAuthSigningIn.Request(
                email: "kai@example.com",
                password: "correct-password"
            )
        ])
    }

    @Test func signInControllerStoresSignupSessionOnlyWhenReturned() async throws {
        let session = SupabaseAuthSession(
            userID: UUID(uuidString: "00000000-0000-0000-0000-000000000222")!,
            accessToken: "signup-access-token",
            refreshToken: "signup-refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1_800_003_600)
        )
        let authClient = CapturingAuthSigningIn(session: session)
        let sessionStore = InMemorySupabaseAuthSessionStore()
        let controller = SaveMVPSignInController(
            authClient: authClient,
            sessionStore: sessionStore
        )

        let result = try await controller.signUp(email: "kai@example.com", password: "new-password")

        #expect(result == SupabaseAuthSignUpResult(userID: session.userID, session: session))
        #expect(sessionStore.load() == session)
        #expect(authClient.signUpRequests == [
            CapturingAuthSigningIn.Request(
                email: "kai@example.com",
                password: "new-password"
            )
        ])
    }

    @Test func signInControllerSignOutClearsStoredSession() async throws {
        let session = SupabaseAuthSession(
            userID: UUID(uuidString: "00000000-0000-0000-0000-000000000333")!,
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1_800_003_600)
        )
        let authClient = CapturingAuthSigningIn(session: session)
        let sessionStore = InMemorySupabaseAuthSessionStore(session: session)
        let controller = SaveMVPSignInController(
            authClient: authClient,
            sessionStore: sessionStore
        )

        controller.signOut()

        #expect(sessionStore.load() == nil)
    }

    @Test func signInControllerRefreshesAndStoresExpiredSession() async throws {
        let expiredSession = SupabaseAuthSession(
            userID: UUID(uuidString: "00000000-0000-0000-0000-000000000333")!,
            accessToken: "expired-access-token",
            refreshToken: "old-refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1_799_999_000)
        )
        let refreshedSession = SupabaseAuthSession(
            userID: expiredSession.userID,
            accessToken: "new-access-token",
            refreshToken: "new-refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1_800_003_600)
        )
        let authClient = CapturingAuthSigningIn(session: refreshedSession)
        let sessionStore = InMemorySupabaseAuthSessionStore(session: expiredSession)
        let controller = SaveMVPSignInController(
            authClient: authClient,
            sessionStore: sessionStore
        )

        let session = try await controller.refreshStoredSession(now: Date(timeIntervalSince1970: 1_800_000_000))

        #expect(session == refreshedSession)
        #expect(sessionStore.load() == refreshedSession)
        #expect(authClient.refreshRequests == ["old-refresh-token"])
    }

    @Test func signInControllerSkipsRefreshForUsableSession() async throws {
        let storedSession = SupabaseAuthSession(
            userID: UUID(uuidString: "00000000-0000-0000-0000-000000000333")!,
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1_800_003_600)
        )
        let authClient = CapturingAuthSigningIn(session: storedSession)
        let sessionStore = InMemorySupabaseAuthSessionStore(session: storedSession)
        let controller = SaveMVPSignInController(
            authClient: authClient,
            sessionStore: sessionStore
        )

        let session = try await controller.refreshStoredSession(now: Date(timeIntervalSince1970: 1_800_000_000))

        #expect(session == storedSession)
        #expect(authClient.refreshRequests.isEmpty)
    }

    @Test func signInControllerFactoryRequiresSupabaseConfiguration() async throws {
        #expect(SaveMVPSignInControllerFactory.make(environment: [:]) == nil)
        #expect(SaveMVPSignInControllerFactory.make(environment: [
            "SAVE_SUPABASE_URL": "https://example.supabase.co",
            "SAVE_SUPABASE_PUBLISHABLE_KEY": "publishable-key"
        ]) != nil)
    }

    @Test func progressStoreFactoryUsesStoredSupabaseSessionWhenConfigured() async throws {
        let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000fed")!
        let progressClient = CapturingSupabaseHTTPClient()
        let sessionStore = InMemorySupabaseAuthSessionStore(session: SupabaseAuthSession(
            userID: userID,
            accessToken: "stored-access-token",
            refreshToken: "stored-refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1_800_003_600)
        ))
        let store = SaveMVPProgressStoreFactory.make(
            environment: [
                "SAVE_SUPABASE_URL": "https://example.supabase.co",
                "SAVE_SUPABASE_PUBLISHABLE_KEY": "publishable-key"
            ],
            sessionStore: sessionStore,
            progressHTTPClient: progressClient
        )

        store.save(SaveMVPPersistedState(hasCompletedOnboarding: true))

        let request = try #require(progressClient.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer stored-access-token")
        let body = try #require(request.httpBody)
        let json = try #require(String(data: body, encoding: .utf8))
        #expect(json.contains(userID.uuidString))
    }

    @Test func progressStoreFactoryUsesLocalStoreWhenSupabaseConfigIsMissing() async throws {
        let store = SaveMVPProgressStoreFactory.make(environment: [:])

        store.save(SaveMVPPersistedState(hasCompletedOnboarding: true))

        #expect(store.load().hasCompletedOnboarding)
    }

    @Test func mvpResetClearsProgress() async throws {
        var state = SaveMVPState()

        state.completeOnboarding()
        state.connect(.gmail)
        state.excludeFirstReviewItem()
        state.resetProgress()

        #expect(!state.hasCompletedOnboarding)
        #expect(state.connectedSources.isEmpty)
        #expect(state.summary.needsReviewCount == 1)
    }

    @Test func receiptOCRParserBuildsDraftFromFixtureText() async throws {
        let draft = try ReceiptOCRParser().parse(Self.fixtureReceiptOCR)

        #expect(draft.merchant == "CVS Pharmacy")
        #expect(draft.totalAmount == 32.47)
        #expect(draft.lineItems.count == 2)
        #expect(draft.lineItems.first?.name == "Bandages")
        #expect(draft.lineItems.first?.amount == 8.99)
    }

    @Test func receiptOCRParserHandlesCommonReceiptFormatting() async throws {
        let draft = try ReceiptOCRParser().parse("""
        CVS Pharmacy
        05/22/2026
        Bandages $8.99
        Saline Solution $23.48
        Subtotal $32.47
        Tax $0.00
        TOTAL $32.47
        """)

        #expect(draft.merchant == "CVS Pharmacy")
        #expect(draft.totalAmount == 32.47)
        #expect(draft.lineItems.map(\.name) == ["Bandages", "Saline Solution"])
        #expect(draft.lineItems.map(\.amount) == [8.99, 23.48])
    }

    @Test func mvpImportsReceiptDraftForReview() async throws {
        let draft = try ReceiptOCRParser().parse(Self.fixtureReceiptOCR)
        var state = SaveMVPState()

        state.importReceiptDraft(draft)

        #expect(state.receipts.contains { $0.merchant == "CVS Pharmacy" })
        #expect(state.summary.needsReviewCount == 3)
    }

    @Test func mvpProgressSnapshotRestoresImportedReceiptDrafts() async throws {
        let draft = try ReceiptOCRParser().parse(Self.fixtureReceiptOCR)
        var state = SaveMVPState()

        state.importReceiptDraft(draft)

        let restored = SaveMVPState(persisted: state.persisted)

        #expect(restored.receipts.contains { $0.merchant == "CVS Pharmacy" })
        #expect(restored.summary.needsReviewCount == 3)
    }

    @Test func mvpClassifiesImportedReceiptLineItemsFromReview() async throws {
        let draft = try ReceiptOCRParser().parse(Self.fixtureReceiptOCR)
        var state = SaveMVPState(receipts: [], claimPackets: [])

        state.importReceiptDraft(draft)
        let firstItem = try #require(state.receipts.first?.lineItems.first)
        let secondItem = try #require(state.receipts.first?.lineItems.dropFirst().first)

        state.classifyLineItem(firstItem.id, as: .fsaEligible)
        state.classifyLineItem(secondItem.id, as: .notEligible)

        #expect(state.summary.needsReviewCount == 0)
        #expect(state.summary.totalClaimable == 8.99)
        #expect(state.taxExport.totalMedicalExpenses == 8.99)
    }

    @Test func mvpEditsImportedReceiptMetadataAndLineItems() async throws {
        let draft = try ReceiptOCRParser().parse(Self.fixtureReceiptOCR)
        var state = SaveMVPState(receipts: [], claimPackets: [])

        state.importReceiptDraft(draft)
        let receipt = try #require(state.receipts.first)
        let firstItem = try #require(receipt.lineItems.first)
        let editedDate = Date(timeIntervalSince1970: 1_800_000_000)

        state.editReceipt(receipt.id, merchant: "CVS Health", date: editedDate)
        state.editLineItem(firstItem.id, name: "Flexible bandages", amount: 9.49)

        let editedReceipt = try #require(state.receipts.first)
        #expect(editedReceipt.merchant == "CVS Health")
        #expect(editedReceipt.date == editedDate)
        #expect(editedReceipt.lineItems.first?.name == "Flexible bandages")
        #expect(editedReceipt.lineItems.first?.amount == 9.49)
        #expect(editedReceipt.total == 32.97)
    }

    @Test func mvpProgressSnapshotRestoresEditedReceiptFields() async throws {
        let draft = try ReceiptOCRParser().parse(Self.fixtureReceiptOCR)
        var state = SaveMVPState(receipts: [], claimPackets: [])

        state.importReceiptDraft(draft)
        let receipt = try #require(state.receipts.first)
        let firstItem = try #require(receipt.lineItems.first)
        let editedDate = Date(timeIntervalSince1970: 1_800_000_000)

        state.editReceipt(receipt.id, merchant: "CVS Health", date: editedDate)
        state.editLineItem(firstItem.id, name: "Flexible bandages", amount: 9.49)

        let restored = SaveMVPState(persisted: state.persisted)
        let restoredReceipt = try #require(restored.receipts.first)

        #expect(restoredReceipt.merchant == "CVS Health")
        #expect(restoredReceipt.date == editedDate)
        #expect(restoredReceipt.lineItems.first?.name == "Flexible bandages")
        #expect(restoredReceipt.lineItems.first?.amount == 9.49)
    }

    @Test func mvpProgressSnapshotRestoresClassifiedImportedReceiptLineItems() async throws {
        let draft = try ReceiptOCRParser().parse(Self.fixtureReceiptOCR)
        var state = SaveMVPState(receipts: [], claimPackets: [])

        state.importReceiptDraft(draft)
        let firstItem = try #require(state.receipts.first?.lineItems.first)

        state.classifyLineItem(firstItem.id, as: .fsaEligible)

        let restored = SaveMVPState(persisted: state.persisted)

        #expect(restored.summary.needsReviewCount == 2)
        #expect(restored.summary.totalClaimable == 743.17)
        #expect(restored.taxExport.totalMedicalExpenses == 943.17)
    }

    private static let fixtureReceiptOCR = """
    CVS Pharmacy
    2026-05-22
    Bandages 8.99
    Saline Solution 23.48
    Total 32.47
    """
}

private final class CapturingAuthSigningIn: SupabaseAuthSigningIn {
    struct Request: Equatable {
        let email: String
        let password: String
    }

    private(set) var requests: [Request] = []
    private(set) var signUpRequests: [Request] = []
    private(set) var refreshRequests: [String] = []
    let session: SupabaseAuthSession

    init(session: SupabaseAuthSession) {
        self.session = session
    }

    func signIn(email: String, password: String) async throws -> SupabaseAuthSession {
        requests.append(Request(email: email, password: password))
        return session
    }

    func signUp(email: String, password: String) async throws -> SupabaseAuthSignUpResult {
        signUpRequests.append(Request(email: email, password: password))
        return SupabaseAuthSignUpResult(userID: session.userID, session: session)
    }

    func refreshSession(refreshToken: String) async throws -> SupabaseAuthSession {
        refreshRequests.append(refreshToken)
        return session
    }
}

private final class CapturingSaveMVPRemoteProgressSyncer: SaveMVPRemoteProgressSyncing {
    private(set) var records: [SupabaseSaveMVPProgressRecord] = []
    var result: Result<Void, Error> = .success(())

    func push(_ record: SupabaseSaveMVPProgressRecord, completion: @escaping (Result<Void, Error>) -> Void) {
        records.append(record)
        completion(result)
    }
}

private final class CapturingSupabaseHTTPClient: SupabaseHTTPClient {
    private(set) var requests: [URLRequest] = []

    func send(_ request: URLRequest, completion: @escaping (Result<Void, Error>) -> Void) {
        requests.append(request)
        completion(.success(()))
    }
}

private final class DeferredSupabaseHTTPClient: SupabaseHTTPClient {
    private(set) var requests: [URLRequest] = []
    private var completions: [(Result<Void, Error>) -> Void] = []

    var requestedTables: [String] {
        requests.compactMap { $0.url?.lastPathComponent }
    }

    func send(_ request: URLRequest, completion: @escaping (Result<Void, Error>) -> Void) {
        requests.append(request)
        completions.append(completion)
    }

    func completeNext(_ result: Result<Void, Error> = .success(())) {
        completions.removeFirst()(result)
    }
}

private final class CapturingSupabaseAuthHTTPClient: SupabaseAuthHTTPClient {
    private(set) var requests: [URLRequest] = []
    let responseData: Data

    init(responseData: Data) {
        self.responseData = responseData
    }

    func data(for request: URLRequest) async throws -> Data {
        requests.append(request)
        return responseData
    }
}

private final class QueueingSupabaseAuthHTTPClient: SupabaseAuthHTTPClient {
    private(set) var requests: [URLRequest] = []
    private var responseData: [Data]

    var requestedTables: [String] {
        requests.compactMap { $0.url?.lastPathComponent }
    }

    init(responseData: [Data]) {
        self.responseData = responseData
    }

    func data(for request: URLRequest) async throws -> Data {
        requests.append(request)
        return responseData.removeFirst()
    }
}

private final class StubRemoteProgressLoader: SaveMVPRemoteProgressLoading {
    let snapshot: SaveMVPPersistedState?

    init(snapshot: SaveMVPPersistedState?) {
        self.snapshot = snapshot
    }

    func load() async throws -> SaveMVPPersistedState? {
        snapshot
    }
}

private extension URLRequest {
    func firstJSONArrayObjectStringValue(forKey key: String) throws -> String? {
        guard let httpBody else {
            return nil
        }

        let value = try JSONSerialization.jsonObject(with: httpBody)
        guard let rows = value as? [[String: Any]] else {
            return nil
        }

        return rows.first?[key] as? String
    }
}
