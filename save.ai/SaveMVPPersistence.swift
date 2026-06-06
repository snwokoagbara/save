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
    let accessToken: String

    init?(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        guard let projectURLString = environment["SAVE_SUPABASE_URL"],
              let projectURL = URL(string: projectURLString),
              let publishableKey = environment["SAVE_SUPABASE_PUBLISHABLE_KEY"],
              let accessToken = environment["SAVE_SUPABASE_ACCESS_TOKEN"] else {
            return nil
        }

        self.init(
            projectURL: projectURL,
            publishableKey: publishableKey,
            accessToken: accessToken
        )
    }

    init(projectURL: URL, publishableKey: String, accessToken: String) {
        self.projectURL = projectURL
        self.publishableKey = publishableKey
        self.accessToken = accessToken
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
    private let httpClient: SupabaseHTTPClient

    init(
        configuration: SupabaseSaveMVPConfiguration,
        httpClient: SupabaseHTTPClient = URLSessionSupabaseHTTPClient()
    ) {
        self.configuration = configuration
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
        request.setValue("Bearer \(configuration.accessToken)", forHTTPHeaderField: "Authorization")
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
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SaveMVPProgressStoring {
        let localStore = UserDefaultsSaveMVPProgressStore()
        guard let configuration = SupabaseSaveMVPConfiguration(environment: environment),
              let userIDString = environment["SAVE_MVP_USER_ID"],
              let userID = UUID(uuidString: userIDString) else {
            return localStore
        }

        return SyncingSaveMVPProgressStore(
            localStore: localStore,
            remoteSyncer: SupabaseRESTSaveMVPProgressSyncer(configuration: configuration),
            userID: userID
        )
    }
}
