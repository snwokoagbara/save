import Foundation

struct ReceiptLineItemClassification: Codable, Equatable {
    let merchant: String
    let purchasedAt: Date
    let itemName: String
    let amount: Double
    let eligibility: Eligibility
}

struct SaveMVPPersistedState: Codable, Equatable {
    var hasCompletedOnboarding: Bool
    var connectedSources: Set<ConnectedSource>
    var excludedFirstReviewItem: Bool
    var preparedFirstDraftClaim: Bool
    var exportedTaxReport: Bool
    var importedSampleReceipt: Bool
    var importedReceiptDrafts: [ReceiptDraft]
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
    func push(_ record: SupabaseSaveMVPProgressRecord)
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

    private struct PasswordSignInPayload: Encodable {
        let email: String
        let password: String
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
}

enum SupabaseAuthError: Error {
    case invalidURL
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
    func send(_ request: URLRequest)
}

struct URLSessionSupabaseHTTPClient: SupabaseHTTPClient {
    func send(_ request: URLRequest) {
        URLSession.shared.dataTask(with: request).resume()
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

    func push(_ record: SupabaseSaveMVPProgressRecord) {
        guard let request = makeRequest(for: record) else {
            return
        }

        httpClient.send(request)
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

struct SyncingSaveMVPProgressStore: SaveMVPProgressStoring {
    private let localStore: SaveMVPProgressStoring
    private let remoteSyncer: SaveMVPRemoteProgressSyncing
    private let userID: UUID
    private let now: () -> Date

    init(
        localStore: SaveMVPProgressStoring,
        remoteSyncer: SaveMVPRemoteProgressSyncing,
        userID: UUID,
        now: @escaping () -> Date = Date.init
    ) {
        self.localStore = localStore
        self.remoteSyncer = remoteSyncer
        self.userID = userID
        self.now = now
    }

    func load() -> SaveMVPPersistedState {
        localStore.load()
    }

    func save(_ state: SaveMVPPersistedState) {
        localStore.save(state)
        remoteSyncer.push(
            SupabaseSaveMVPProgressRecord(
                userID: userID,
                state: state,
                updatedAt: now()
            )
        )
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
        now: Date = Date()
    ) -> SaveMVPProgressStoring {
        let localStore = UserDefaultsSaveMVPProgressStore()
        guard let configuration = SupabaseSaveMVPConfiguration(environment: environment),
              let session = sessionStore.load(),
              session.isUsable(now: now) else {
            return localStore
        }

        return SyncingSaveMVPProgressStore(
            localStore: localStore,
            remoteSyncer: SupabaseRESTSaveMVPProgressSyncer(
                configuration: configuration,
                session: session,
                httpClient: progressHTTPClient
            ),
            userID: session.userID
        )
    }
}
