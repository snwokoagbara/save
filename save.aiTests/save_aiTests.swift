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
        )

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
}

private final class CapturingSaveMVPRemoteProgressSyncer: SaveMVPRemoteProgressSyncing {
    private(set) var records: [SupabaseSaveMVPProgressRecord] = []

    func push(_ record: SupabaseSaveMVPProgressRecord) {
        records.append(record)
    }
}

private final class CapturingSupabaseHTTPClient: SupabaseHTTPClient {
    private(set) var requests: [URLRequest] = []

    func send(_ request: URLRequest) {
        requests.append(request)
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
