import CryptoKit
import Foundation

struct ReceiptLineItemClassification: Codable, Equatable {
    let merchant: String
    let purchasedAt: Date
    let itemName: String
    let amount: Double
    let eligibility: Eligibility
}

struct ReceiptEdit: Codable, Equatable {
    let originalMerchant: String
    let originalPurchasedAt: Date
    let merchant: String
    let purchasedAt: Date
}

struct ReceiptLineItemEdit: Codable, Equatable {
    let receiptMerchant: String
    let receiptPurchasedAt: Date
    let originalItemName: String
    let originalAmount: Double
    let itemName: String
    let amount: Double
}

struct SaveMVPPersistedState: Codable, Equatable {
    var hasCompletedOnboarding: Bool
    var connectedSources: Set<ConnectedSource>
    var excludedFirstReviewItem: Bool
    var preparedFirstDraftClaim: Bool
    var exportedTaxReport: Bool
    var importedSampleReceipt: Bool
    var importedReceiptDrafts: [ReceiptDraft]
    var receiptEdits: [ReceiptEdit]
    var receiptLineItemEdits: [ReceiptLineItemEdit]
    var receiptLineItemClassifications: [ReceiptLineItemClassification]
    var submittedClaimAdministratorNames: Set<String>
    var reimbursedClaimAdministratorNames: Set<String>

    init(
        hasCompletedOnboarding: Bool = false,
        connectedSources: Set<ConnectedSource> = [],
        excludedFirstReviewItem: Bool = false,
        preparedFirstDraftClaim: Bool = false,
        exportedTaxReport: Bool = false,
        importedSampleReceipt: Bool = false,
        importedReceiptDrafts: [ReceiptDraft] = [],
        receiptEdits: [ReceiptEdit] = [],
        receiptLineItemEdits: [ReceiptLineItemEdit] = [],
        receiptLineItemClassifications: [ReceiptLineItemClassification] = [],
        submittedClaimAdministratorNames: Set<String> = [],
        reimbursedClaimAdministratorNames: Set<String> = []
    ) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.connectedSources = connectedSources
        self.excludedFirstReviewItem = excludedFirstReviewItem
        self.preparedFirstDraftClaim = preparedFirstDraftClaim
        self.exportedTaxReport = exportedTaxReport
        self.importedSampleReceipt = importedSampleReceipt
        self.importedReceiptDrafts = importedReceiptDrafts
        self.receiptEdits = receiptEdits
        self.receiptLineItemEdits = receiptLineItemEdits
        self.receiptLineItemClassifications = receiptLineItemClassifications
        self.submittedClaimAdministratorNames = submittedClaimAdministratorNames
        self.reimbursedClaimAdministratorNames = reimbursedClaimAdministratorNames
    }

    enum CodingKeys: String, CodingKey {
        case hasCompletedOnboarding
        case connectedSources
        case excludedFirstReviewItem
        case preparedFirstDraftClaim
        case exportedTaxReport
        case importedSampleReceipt
        case importedReceiptDrafts
        case receiptEdits
        case receiptLineItemEdits
        case receiptLineItemClassifications
        case submittedClaimAdministratorNames
        case reimbursedClaimAdministratorNames
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        connectedSources = try container.decodeIfPresent(Set<ConnectedSource>.self, forKey: .connectedSources) ?? []
        excludedFirstReviewItem = try container.decodeIfPresent(Bool.self, forKey: .excludedFirstReviewItem) ?? false
        preparedFirstDraftClaim = try container.decodeIfPresent(Bool.self, forKey: .preparedFirstDraftClaim) ?? false
        exportedTaxReport = try container.decodeIfPresent(Bool.self, forKey: .exportedTaxReport) ?? false
        importedSampleReceipt = try container.decodeIfPresent(Bool.self, forKey: .importedSampleReceipt) ?? false
        importedReceiptDrafts = try container.decodeIfPresent([ReceiptDraft].self, forKey: .importedReceiptDrafts) ?? []
        receiptEdits = try container.decodeIfPresent([ReceiptEdit].self, forKey: .receiptEdits) ?? []
        receiptLineItemEdits = try container.decodeIfPresent([ReceiptLineItemEdit].self, forKey: .receiptLineItemEdits) ?? []
        receiptLineItemClassifications = try container.decodeIfPresent([ReceiptLineItemClassification].self, forKey: .receiptLineItemClassifications) ?? []
        submittedClaimAdministratorNames = try container.decodeIfPresent(Set<String>.self, forKey: .submittedClaimAdministratorNames) ?? []
        reimbursedClaimAdministratorNames = try container.decodeIfPresent(Set<String>.self, forKey: .reimbursedClaimAdministratorNames) ?? []
    }
}

protocol SaveMVPProgressStoring {
    func load() -> SaveMVPPersistedState
    func save(_ state: SaveMVPPersistedState)
}

struct SupabaseSaveMVPProgressRecord: Codable, Equatable {
    let userID: UUID
    let state: SaveMVPPersistedState
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case state
        case updatedAt = "updated_at"
    }
}

protocol SaveMVPRemoteProgressSyncing {
    func push(_ record: SupabaseSaveMVPProgressRecord, completion: @escaping (Result<Void, Error>) -> Void)
}

enum SaveMVPRemoteSyncStatus: Equatable {
    case syncing(Date)
    case synced(Date)
    case failed(Date)
}

protocol SaveMVPRemoteProgressLoading {
    func load() async throws -> SaveMVPPersistedState?
}

struct SupabaseSaveMVPConfiguration: Equatable {
    let projectURL: URL
    let publishableKey: String

    init?(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        guard let projectURLString = environment["SAVE_SUPABASE_URL"],
              let projectURL = URL(string: projectURLString),
              let publishableKey = environment["SAVE_SUPABASE_PUBLISHABLE_KEY"] else {
            return nil
        }

        self.init(
            projectURL: projectURL,
            publishableKey: publishableKey
        )
    }

    init(projectURL: URL, publishableKey: String) {
        self.projectURL = projectURL
        self.publishableKey = publishableKey
    }
}

struct SupabaseAuthSession: Codable, Equatable {
    let userID: UUID
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID
        case accessToken
        case refreshToken
        case expiresAt
    }

    func isUsable(now: Date = Date()) -> Bool {
        guard let expiresAt else {
            return true
        }

        return expiresAt > now
    }
}

struct SupabaseAuthSignUpResult: Equatable {
    let userID: UUID
    let session: SupabaseAuthSession?
}

protocol SupabaseAuthSessionStoring {
    func load() -> SupabaseAuthSession?
    func save(_ session: SupabaseAuthSession)
    func clear()
}

struct UserDefaultsSupabaseAuthSessionStore: SupabaseAuthSessionStoring {
    private let key: String
    private let userDefaults: UserDefaults

    init(
        key: String = "save.supabase.auth.session",
        userDefaults: UserDefaults = .standard
    ) {
        self.key = key
        self.userDefaults = userDefaults
    }

    func load() -> SupabaseAuthSession? {
        guard let data = userDefaults.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder.saveMVP.decode(SupabaseAuthSession.self, from: data)
    }

    func save(_ session: SupabaseAuthSession) {
        guard let data = try? JSONEncoder.saveMVP.encode(session) else {
            return
        }

        userDefaults.set(data, forKey: key)
    }

    func clear() {
        userDefaults.removeObject(forKey: key)
    }
}

final class InMemorySupabaseAuthSessionStore: SupabaseAuthSessionStoring {
    private var session: SupabaseAuthSession?

    init(session: SupabaseAuthSession? = nil) {
        self.session = session
    }

    func load() -> SupabaseAuthSession? {
        session
    }

    func save(_ session: SupabaseAuthSession) {
        self.session = session
    }

    func clear() {
        session = nil
    }
}

protocol SupabaseAuthHTTPClient {
    func data(for request: URLRequest) async throws -> Data
}

protocol SupabaseAuthSigningIn {
    func signIn(email: String, password: String) async throws -> SupabaseAuthSession
    func signUp(email: String, password: String) async throws -> SupabaseAuthSignUpResult
    func refreshSession(refreshToken: String) async throws -> SupabaseAuthSession
}

struct URLSessionSupabaseAuthHTTPClient: SupabaseAuthHTTPClient {
    func data(for request: URLRequest) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }
}

struct SupabaseRESTAuthClient: SupabaseAuthSigningIn {
    private let configuration: SupabaseSaveMVPConfiguration
    private let httpClient: SupabaseAuthHTTPClient
    private let now: () -> Date

    init(
        configuration: SupabaseSaveMVPConfiguration,
        httpClient: SupabaseAuthHTTPClient = URLSessionSupabaseAuthHTTPClient(),
        now: @escaping () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.httpClient = httpClient
        self.now = now
    }

    func signIn(email: String, password: String) async throws -> SupabaseAuthSession {
        var components = URLComponents(
            url: configuration.projectURL
                .appendingPathComponent("auth")
                .appendingPathComponent("v1")
                .appendingPathComponent("token"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "grant_type", value: "password")]

        guard let url = components?.url else {
            throw SupabaseAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder.saveMVP.encode(PasswordSignInPayload(email: email, password: password))
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data = try await httpClient.data(for: request)
        let response = try JSONDecoder.saveMVP.decode(PasswordSignInResponse.self, from: data)
        let expiresAt = response.expiresIn.map { now().addingTimeInterval(TimeInterval($0)) }

        return SupabaseAuthSession(
            userID: response.user.id,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: expiresAt
        )
    }

    func signUp(email: String, password: String) async throws -> SupabaseAuthSignUpResult {
        let url = configuration.projectURL
            .appendingPathComponent("auth")
            .appendingPathComponent("v1")
            .appendingPathComponent("signup")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder.saveMVP.encode(PasswordSignInPayload(email: email, password: password))
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data = try await httpClient.data(for: request)
        let response = try JSONDecoder.saveMVP.decode(PasswordSignUpResponse.self, from: data)
        let userID = try response.resolvedUserID()
        let expiresAt = response.expiresIn.map { now().addingTimeInterval(TimeInterval($0)) }
        let session = response.accessToken.map {
            SupabaseAuthSession(
                userID: userID,
                accessToken: $0,
                refreshToken: response.refreshToken,
                expiresAt: expiresAt
            )
        }

        return SupabaseAuthSignUpResult(userID: userID, session: session)
    }

    func refreshSession(refreshToken: String) async throws -> SupabaseAuthSession {
        var components = URLComponents(
            url: configuration.projectURL
                .appendingPathComponent("auth")
                .appendingPathComponent("v1")
                .appendingPathComponent("token"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]

        guard let url = components?.url else {
            throw SupabaseAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder.saveMVP.encode(RefreshTokenPayload(refreshToken: refreshToken))
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data = try await httpClient.data(for: request)
        let response = try JSONDecoder.saveMVP.decode(PasswordSignInResponse.self, from: data)
        let expiresAt = response.expiresIn.map { now().addingTimeInterval(TimeInterval($0)) }

        return SupabaseAuthSession(
            userID: response.user.id,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: expiresAt
        )
    }

    private struct PasswordSignInPayload: Encodable {
        let email: String
        let password: String
    }

    private struct RefreshTokenPayload: Encodable {
        let refreshToken: String

        enum CodingKeys: String, CodingKey {
            case refreshToken = "refresh_token"
        }
    }

    private struct PasswordSignInResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int?
        let user: User

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case user
        }

        struct User: Decodable {
            let id: UUID
        }
    }

    private struct PasswordSignUpResponse: Decodable {
        let id: UUID?
        let accessToken: String?
        let refreshToken: String?
        let expiresIn: Int?
        let user: User?

        enum CodingKeys: String, CodingKey {
            case id
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case user
        }

        func resolvedUserID() throws -> UUID {
            if let user {
                return user.id
            }

            if let id {
                return id
            }

            throw SupabaseAuthError.missingUserID
        }

        struct User: Decodable {
            let id: UUID
        }
    }
}

enum SupabaseAuthError: Error {
    case invalidURL
    case missingUserID
}

struct SaveMVPSignInController {
    private let authClient: SupabaseAuthSigningIn
    private let sessionStore: SupabaseAuthSessionStoring

    init(
        authClient: SupabaseAuthSigningIn,
        sessionStore: SupabaseAuthSessionStoring
    ) {
        self.authClient = authClient
        self.sessionStore = sessionStore
    }

    func signIn(email: String, password: String) async throws -> SupabaseAuthSession {
        let session = try await authClient.signIn(email: email, password: password)
        sessionStore.save(session)
        return session
    }

    func signUp(email: String, password: String) async throws -> SupabaseAuthSignUpResult {
        let result = try await authClient.signUp(email: email, password: password)
        if let session = result.session {
            sessionStore.save(session)
        }
        return result
    }

    func signOut() {
        sessionStore.clear()
    }

    func refreshStoredSession(now: Date = Date()) async throws -> SupabaseAuthSession? {
        guard let session = sessionStore.load() else {
            return nil
        }

        guard !session.isUsable(now: now) else {
            return session
        }

        guard let refreshToken = session.refreshToken else {
            return nil
        }

        let refreshedSession = try await authClient.refreshSession(refreshToken: refreshToken)
        sessionStore.save(refreshedSession)
        return refreshedSession
    }
}

enum SaveMVPSignInControllerFactory {
    static func make(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        sessionStore: SupabaseAuthSessionStoring = UserDefaultsSupabaseAuthSessionStore()
    ) -> SaveMVPSignInController? {
        guard let configuration = SupabaseSaveMVPConfiguration(environment: environment) else {
            return nil
        }

        return SaveMVPSignInController(
            authClient: SupabaseRESTAuthClient(configuration: configuration),
            sessionStore: sessionStore
        )
    }
}

protocol SupabaseHTTPClient {
    func send(_ request: URLRequest, completion: @escaping (Result<Void, Error>) -> Void)
}

struct URLSessionSupabaseHTTPClient: SupabaseHTTPClient {
    func send(_ request: URLRequest, completion: @escaping (Result<Void, Error>) -> Void) {
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                completion(.failure(SupabaseProgressSyncError.httpStatus(httpResponse.statusCode)))
                return
            }

            completion(.success(()))
        }
        .resume()
    }
}

enum SupabaseProgressSyncError: LocalizedError, Equatable {
    case invalidRequest
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "Progress sync request could not be created."
        case .httpStatus(let statusCode):
            return "Progress sync failed with HTTP \(statusCode)."
        }
    }
}

struct SupabaseRESTSaveMVPProgressLoader: SaveMVPRemoteProgressLoading {
    private let configuration: SupabaseSaveMVPConfiguration
    private let session: SupabaseAuthSession
    private let httpClient: SupabaseAuthHTTPClient

    init(
        configuration: SupabaseSaveMVPConfiguration,
        session: SupabaseAuthSession,
        httpClient: SupabaseAuthHTTPClient = URLSessionSupabaseAuthHTTPClient()
    ) {
        self.configuration = configuration
        self.session = session
        self.httpClient = httpClient
    }

    func load() async throws -> SaveMVPPersistedState? {
        guard let request = makeRequest() else {
            throw SupabaseAuthError.invalidURL
        }

        let data = try await httpClient.data(for: request)
        return try JSONDecoder.saveMVP.decode([SnapshotResponse].self, from: data).first?.state
    }

    private func makeRequest() -> URLRequest? {
        var components = URLComponents(
            url: configuration.projectURL
                .appendingPathComponent("rest")
                .appendingPathComponent("v1")
                .appendingPathComponent("mvp_progress_snapshots"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "select", value: "state"),
            URLQueryItem(name: "user_id", value: "eq.\(session.userID.uuidString.lowercased())"),
            URLQueryItem(name: "limit", value: "1")
        ]

        guard let url = components?.url else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private struct SnapshotResponse: Decodable {
        let state: SaveMVPPersistedState
    }
}

struct SupabaseRESTSaveMVPProgressSyncer: SaveMVPRemoteProgressSyncing {
    private let configuration: SupabaseSaveMVPConfiguration
    private let session: SupabaseAuthSession
    private let httpClient: SupabaseHTTPClient

    init(
        configuration: SupabaseSaveMVPConfiguration,
        session: SupabaseAuthSession,
        httpClient: SupabaseHTTPClient = URLSessionSupabaseHTTPClient()
    ) {
        self.configuration = configuration
        self.session = session
        self.httpClient = httpClient
    }

    func push(_ record: SupabaseSaveMVPProgressRecord, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let request = makeRequest(for: record) else {
            completion(.failure(SupabaseProgressSyncError.invalidRequest))
            return
        }

        httpClient.send(request, completion: completion)
    }

    private func makeRequest(for record: SupabaseSaveMVPProgressRecord) -> URLRequest? {
        let url = configuration.projectURL
            .appendingPathComponent("rest")
            .appendingPathComponent("v1")
            .appendingPathComponent("mvp_progress_snapshots")

        guard let body = try? JSONEncoder.saveMVP.encode(record) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        return request
    }
}

struct SupabaseRESTSaveMVPFirstClassProgressSyncer: SaveMVPRemoteProgressSyncing {
    private let configuration: SupabaseSaveMVPConfiguration
    private let session: SupabaseAuthSession
    private let httpClient: SupabaseHTTPClient

    init(
        configuration: SupabaseSaveMVPConfiguration,
        session: SupabaseAuthSession,
        httpClient: SupabaseHTTPClient = URLSessionSupabaseHTTPClient()
    ) {
        self.configuration = configuration
        self.session = session
        self.httpClient = httpClient
    }

    func push(_ record: SupabaseSaveMVPProgressRecord, completion: @escaping (Result<Void, Error>) -> Void) {
        let state = SaveMVPState(persisted: record.state)
        let rows = SupabaseFirstClassRows(userID: record.userID, state: state)
        sendRequests(
            [
                makeRequest(table: "receipts", rows: rows.receipts),
                makeRequest(table: "receipt_line_items", rows: rows.lineItems),
                makeRequest(table: "claim_packets", rows: rows.claimPackets),
                makeRequest(table: "tax_exports", rows: rows.taxExports)
            ],
            completion: completion
        )
    }

    private func sendRequests(_ requests: [URLRequest?], completion: @escaping (Result<Void, Error>) -> Void) {
        sendRequest(at: 0, in: requests, completion: completion)
    }

    private func sendRequest(
        at index: Int,
        in requests: [URLRequest?],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard index < requests.count else {
            completion(.success(()))
            return
        }

        guard let request = requests[index] else {
            completion(.failure(SupabaseProgressSyncError.invalidRequest))
            return
        }

        httpClient.send(request) { result in
            switch result {
            case .success:
                sendRequest(at: index + 1, in: requests, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func makeRequest<Row: Encodable>(table: String, rows: [Row]) -> URLRequest? {
        let url = configuration.projectURL
            .appendingPathComponent("rest")
            .appendingPathComponent("v1")
            .appendingPathComponent(table)

        guard let body = try? JSONEncoder.saveMVP.encode(rows) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        return request
    }
}

private struct SupabaseFirstClassRows {
    let receipts: [SupabaseReceiptRow]
    let lineItems: [SupabaseReceiptLineItemRow]
    let claimPackets: [SupabaseClaimPacketRow]
    let taxExports: [SupabaseTaxExportRow]

    init(userID: UUID, state: SaveMVPState) {
        var lineItemRows: [SupabaseReceiptLineItemRow] = []

        receipts = state.receipts.map { receipt in
            let receiptID = SupabaseDeterministicID.uuid(
                for: "receipt|\(userID.uuidString)|\(receipt.merchant)|\(receipt.date.saveMVPDay)|\(receipt.source.rawValue)|\(receipt.total)"
            )
            receipt.lineItems.enumerated().forEach { index, item in
                let lineItemID = SupabaseDeterministicID.uuid(
                    for: "line-item|\(receiptID.uuidString)|\(index)|\(item.name)|\(item.amount)"
                )
                lineItemRows.append(
                    SupabaseReceiptLineItemRow(
                        id: lineItemID,
                        userID: userID,
                        receiptID: receiptID,
                        originalText: item.name,
                        normalizedName: item.name,
                        amount: item.amount,
                        eligibility: item.eligibility.supabaseValue,
                        confidence: item.confidence
                    )
                )
            }

            return SupabaseReceiptRow(
                id: receiptID,
                userID: userID,
                source: receipt.source.supabaseValue,
                status: receipt.hasNeedsReviewItem ? "needs_review" : "classified",
                merchant: receipt.merchant,
                purchasedAt: receipt.date.saveMVPDay,
                totalAmount: receipt.total
            )
        }
        lineItems = lineItemRows

        claimPackets = state.claimPackets.map { packet in
            SupabaseClaimPacketRow(
                id: SupabaseDeterministicID.uuid(
                    for: "claim-packet|\(userID.uuidString)|\(packet.administratorName)|\(packet.total)|\(packet.status.rawValue)"
                ),
                userID: userID,
                administratorName: packet.administratorName,
                status: packet.status.supabaseValue,
                submissionMode: packet.submissionMode.supabaseValue,
                claimAmount: packet.total
            )
        }

        taxExports = [
            SupabaseTaxExportRow(
                id: SupabaseDeterministicID.uuid(
                    for: "tax-export|\(userID.uuidString)|\(state.taxExport.year)|\(state.taxExport.totalMedicalExpenses)"
                ),
                userID: userID,
                taxYear: state.taxExport.year,
                status: state.taxReportArtifact == nil ? "draft" : "generated",
                totalMedicalExpenses: state.taxExport.totalMedicalExpenses,
                generatedAt: state.taxReportArtifact == nil ? nil : Date()
            )
        ]
    }
}

private struct SupabaseReceiptRow: Encodable {
    let id: UUID
    let userID: UUID
    let source: String
    let status: String
    let merchant: String
    let purchasedAt: String
    let totalAmount: Double

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case source
        case status
        case merchant
        case purchasedAt = "purchased_at"
        case totalAmount = "total_amount"
    }
}

private struct SupabaseReceiptLineItemRow: Encodable {
    let id: UUID
    let userID: UUID
    let receiptID: UUID
    let originalText: String
    let normalizedName: String
    let amount: Double
    let eligibility: String
    let confidence: Double

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case receiptID = "receipt_id"
        case originalText = "original_text"
        case normalizedName = "normalized_name"
        case amount
        case eligibility
        case confidence
    }
}

private struct SupabaseClaimPacketRow: Encodable {
    let id: UUID
    let userID: UUID
    let administratorName: String
    let status: String
    let submissionMode: String
    let claimAmount: Double

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case administratorName = "administrator_name"
        case status
        case submissionMode = "submission_mode"
        case claimAmount = "claim_amount"
    }
}

private struct SupabaseTaxExportRow: Encodable {
    let id: UUID
    let userID: UUID
    let taxYear: Int
    let status: String
    let totalMedicalExpenses: Double
    let generatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case taxYear = "tax_year"
        case status
        case totalMedicalExpenses = "total_medical_expenses"
        case generatedAt = "generated_at"
    }
}

private enum SupabaseDeterministicID {
    static func uuid(for key: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

private extension ReceiptSource {
    var supabaseValue: String {
        switch self {
        case .camera:
            return "camera"
        case .gmail:
            return "gmail"
        case .bank:
            return "bank_match"
        case .forwardedEmail:
            return "forwarded_email"
        }
    }
}

private extension Eligibility {
    var supabaseValue: String {
        switch self {
        case .fsaEligible:
            return "fsa_eligible"
        case .hsaEligible:
            return "hsa_eligible"
        case .scheduleADeductible:
            return "schedule_a_deductible"
        case .notEligible:
            return "not_eligible"
        case .needsReview:
            return "needs_review"
        }
    }
}

private extension ClaimStatus {
    var supabaseValue: String {
        switch self {
        case .draft:
            return "draft"
        case .ready:
            return "ready"
        case .submittedByUser:
            return "submitted_by_user"
        case .submittedInApp:
            return "submitted_in_app"
        case .reimbursed:
            return "reimbursed"
        case .rejected:
            return "rejected"
        case .needsAction:
            return "needs_action"
        }
    }
}

private extension SubmissionMode {
    var supabaseValue: String {
        switch self {
        case .guidedPacket:
            return "guided_packet"
        case .inAppSubmission:
            return "in_app_submission"
        }
    }
}

private extension Date {
    var saveMVPDay: String {
        Self.saveMVPDayFormatter.string(from: self)
    }

    private static let saveMVPDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct CompositeSaveMVPRemoteProgressSyncer: SaveMVPRemoteProgressSyncing {
    private let syncers: [SaveMVPRemoteProgressSyncing]

    init(syncers: [SaveMVPRemoteProgressSyncing]) {
        self.syncers = syncers
    }

    func push(_ record: SupabaseSaveMVPProgressRecord, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !syncers.isEmpty else {
            completion(.success(()))
            return
        }

        var firstError: Error?
        let lock = NSLock()
        let group = DispatchGroup()

        syncers.forEach { syncer in
            group.enter()
            syncer.push(record) { result in
                if case .failure(let error) = result {
                    lock.lock()
                    if firstError == nil {
                        firstError = error
                    }
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .global()) {
            if let firstError {
                completion(.failure(firstError))
            } else {
                completion(.success(()))
            }
        }
    }
}

struct SyncingSaveMVPProgressStore: SaveMVPProgressStoring {
    private let localStore: SaveMVPProgressStoring
    private let remoteSyncer: SaveMVPRemoteProgressSyncing
    private let userID: UUID
    private let now: () -> Date
    private let remoteSyncStatusChanged: (SaveMVPRemoteSyncStatus) -> Void

    init(
        localStore: SaveMVPProgressStoring,
        remoteSyncer: SaveMVPRemoteProgressSyncing,
        userID: UUID,
        now: @escaping () -> Date = Date.init,
        remoteSyncStatusChanged: @escaping (SaveMVPRemoteSyncStatus) -> Void = { _ in }
    ) {
        self.localStore = localStore
        self.remoteSyncer = remoteSyncer
        self.userID = userID
        self.now = now
        self.remoteSyncStatusChanged = remoteSyncStatusChanged
    }

    func load() -> SaveMVPPersistedState {
        localStore.load()
    }

    func save(_ state: SaveMVPPersistedState) {
        localStore.save(state)
        let updatedAt = now()
        remoteSyncStatusChanged(.syncing(updatedAt))
        remoteSyncer.push(
            SupabaseSaveMVPProgressRecord(
                userID: userID,
                state: state,
                updatedAt: updatedAt
            )
        ) { result in
            switch result {
            case .success:
                remoteSyncStatusChanged(.synced(updatedAt))
            case .failure:
                remoteSyncStatusChanged(.failed(updatedAt))
            }
        }
    }
}

extension JSONEncoder {
    static var saveMVP: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var saveMVP: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

struct UserDefaultsSaveMVPProgressStore: SaveMVPProgressStoring {
    private let key: String
    private let userDefaults: UserDefaults

    init(
        key: String = "save.mvp.progress",
        userDefaults: UserDefaults = .standard
    ) {
        self.key = key
        self.userDefaults = userDefaults
    }

    func load() -> SaveMVPPersistedState {
        guard let data = userDefaults.data(forKey: key),
              let state = try? JSONDecoder.saveMVP.decode(SaveMVPPersistedState.self, from: data) else {
            return SaveMVPPersistedState()
        }

        return state
    }

    func save(_ state: SaveMVPPersistedState) {
        guard let data = try? JSONEncoder.saveMVP.encode(state) else {
            return
        }

        userDefaults.set(data, forKey: key)
    }
}

final class InMemorySaveMVPProgressStore: SaveMVPProgressStoring {
    private var state: SaveMVPPersistedState

    init(state: SaveMVPPersistedState = SaveMVPPersistedState()) {
        self.state = state
    }

    func load() -> SaveMVPPersistedState {
        state
    }

    func save(_ state: SaveMVPPersistedState) {
        self.state = state
    }
}

enum SaveMVPProgressStoreFactory {
    static func make(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        sessionStore: SupabaseAuthSessionStoring = UserDefaultsSupabaseAuthSessionStore(),
        progressHTTPClient: SupabaseHTTPClient = URLSessionSupabaseHTTPClient(),
        now: Date = Date(),
        remoteSyncStatusChanged: @escaping (SaveMVPRemoteSyncStatus) -> Void = { _ in }
    ) -> SaveMVPProgressStoring {
        let localStore = UserDefaultsSaveMVPProgressStore()
        guard let configuration = SupabaseSaveMVPConfiguration(environment: environment),
              let session = sessionStore.load(),
              session.isUsable(now: now) else {
            return localStore
        }

        return SyncingSaveMVPProgressStore(
            localStore: localStore,
            remoteSyncer: CompositeSaveMVPRemoteProgressSyncer(
                syncers: [
                    SupabaseRESTSaveMVPProgressSyncer(
                        configuration: configuration,
                        session: session,
                        httpClient: progressHTTPClient
                    ),
                    SupabaseRESTSaveMVPFirstClassProgressSyncer(
                        configuration: configuration,
                        session: session,
                        httpClient: progressHTTPClient
                    )
                ]
            ),
            userID: session.userID,
            remoteSyncStatusChanged: remoteSyncStatusChanged
        )
    }
}

enum SaveMVPRemoteProgressLoaderFactory {
    static func make(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        session: SupabaseAuthSession
    ) -> SaveMVPRemoteProgressLoading? {
        guard let configuration = SupabaseSaveMVPConfiguration(environment: environment),
              session.isUsable() else {
            return nil
        }

        return SupabaseRESTSaveMVPProgressLoader(
            configuration: configuration,
            session: session
        )
    }
}
