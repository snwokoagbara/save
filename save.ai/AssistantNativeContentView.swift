import PhotosUI
import SwiftUI
import UIKit

struct AssistantNativeContentView: View {
    @Environment(\.openURL) private var openURL
    private let progressStoreFactory: (@escaping (SaveMVPRemoteSyncStatus) -> Void) -> SaveMVPProgressStoring
    private let remoteProgressLoaderFactory: (SupabaseAuthSession) -> SaveMVPRemoteProgressLoading?
    private let administratorTemplateLoaderFactory: (SupabaseAuthSession) -> ClaimAdministratorTemplateLoading?
    private let gmailConnectionControllerFactory: (SupabaseAuthSession) -> GmailConnectionStarting?
    private let gmailReceiptImporterFactory: (SupabaseAuthSession) -> GmailReceiptImporting?
    private let gmailDisconnectControllerFactory: (SupabaseAuthSession) -> GmailDisconnecting?
    private let gmailConfigurationCheckerFactory: (SupabaseAuthSession) -> GmailConfigurationChecking?
    private let gmailConnectionLoaderFactory: (SupabaseAuthSession) -> GmailConnectionLoading?
    private let signInController: SaveMVPSignInController?
    @State private var progressStore: SaveMVPProgressStoring
    @State private var state: SaveMVPState
    @State private var administratorTemplates: [ClaimAdministratorTemplate]
    @State private var pendingGmailAuthorizationStart: GmailAuthorizationStart?
    @State private var gmailConnectionError: String?
    @State private var isConnectingGmail = false
    @State private var isImportingGmail = false
    @State private var isDisconnectingGmail = false
    @State private var liveGmailConnection: GmailConnection?
    @State private var gmailLastScannedAt: Date?
    @State private var authSession: SupabaseAuthSession?
    @State private var remoteSyncStatus: SaveMVPRemoteSyncStatus?
    @State private var hasAttemptedRemoteProgressLoad = false
    @State private var isShowingSignIn = false
    @State private var isShowingReceiptIntake = false
    @State private var receiptReviewRoute: ReceiptReviewRoute?
    @State private var pendingReviewReceiptID: UUID?
    @State private var claimPacketRoute: ClaimPacketRoute?
    @State private var isShowingTaxExport = false

    init(
        progressStore: SaveMVPProgressStoring = UserDefaultsSaveMVPProgressStore(),
        progressStoreFactory: (((@escaping (SaveMVPRemoteSyncStatus) -> Void) -> SaveMVPProgressStoring))? = nil,
        remoteProgressLoaderFactory: @escaping (SupabaseAuthSession) -> SaveMVPRemoteProgressLoading? = { _ in nil },
        administratorTemplateLoaderFactory: @escaping (SupabaseAuthSession) -> ClaimAdministratorTemplateLoading? = { _ in nil },
        gmailConnectionControllerFactory: @escaping (SupabaseAuthSession) -> GmailConnectionStarting? = { _ in nil },
        gmailReceiptImporterFactory: @escaping (SupabaseAuthSession) -> GmailReceiptImporting? = { _ in nil },
        gmailDisconnectControllerFactory: @escaping (SupabaseAuthSession) -> GmailDisconnecting? = { _ in nil },
        gmailConfigurationCheckerFactory: @escaping (SupabaseAuthSession) -> GmailConfigurationChecking? = { _ in nil },
        gmailConnectionLoaderFactory: @escaping (SupabaseAuthSession) -> GmailConnectionLoading? = { _ in nil },
        signInController: SaveMVPSignInController? = nil,
        authSession: SupabaseAuthSession? = nil
    ) {
        self.progressStoreFactory = progressStoreFactory ?? { _ in progressStore }
        self.remoteProgressLoaderFactory = remoteProgressLoaderFactory
        self.administratorTemplateLoaderFactory = administratorTemplateLoaderFactory
        self.gmailConnectionControllerFactory = gmailConnectionControllerFactory
        self.gmailReceiptImporterFactory = gmailReceiptImporterFactory
        self.gmailDisconnectControllerFactory = gmailDisconnectControllerFactory
        self.gmailConfigurationCheckerFactory = gmailConfigurationCheckerFactory
        self.gmailConnectionLoaderFactory = gmailConnectionLoaderFactory
        self.signInController = signInController
        if ProcessInfo.processInfo.arguments.contains("RESET_SAVE_MVP_PROGRESS") {
            progressStore.save(SaveMVPPersistedState())
        }
        _progressStore = State(initialValue: progressStore)
        _state = State(initialValue: SaveMVPState(persisted: progressStore.load()))
        _administratorTemplates = State(initialValue: ClaimAdministratorTemplateLibrary.defaultTemplates)
        _authSession = State(initialValue: authSession)
    }

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        sessionStore: SupabaseAuthSessionStoring = UserDefaultsSupabaseAuthSessionStore()
    ) {
        let makeProgressStore: (@escaping (SaveMVPRemoteSyncStatus) -> Void) -> SaveMVPProgressStoring = { remoteSyncStatusChanged in
            SaveMVPProgressStoreFactory.make(
                environment: environment,
                sessionStore: sessionStore,
                remoteSyncStatusChanged: remoteSyncStatusChanged
            )
        }
        let progressStore = makeProgressStore { _ in }
        self.init(
            progressStore: progressStore,
            progressStoreFactory: makeProgressStore,
            remoteProgressLoaderFactory: { session in
                SaveMVPRemoteProgressLoaderFactory.make(
                    environment: environment,
                    session: session
                )
            },
            administratorTemplateLoaderFactory: { session in
                ClaimAdministratorTemplateLoaderFactory.make(
                    environment: environment,
                    session: session
                )
            },
            gmailConnectionControllerFactory: { session in
                GmailConnectionControllerFactory.make(
                    environment: environment,
                    session: session
                )
            },
            gmailReceiptImporterFactory: { session in
                GmailReceiptImporterFactory.make(
                    environment: environment,
                    session: session
                )
            },
            gmailDisconnectControllerFactory: { session in
                GmailDisconnectControllerFactory.make(
                    environment: environment,
                    session: session
                )
            },
            gmailConfigurationCheckerFactory: { session in
                GmailConfigurationCheckerFactory.make(
                    environment: environment,
                    session: session
                )
            },
            gmailConnectionLoaderFactory: { session in
                GmailConnectionLoaderFactory.make(
                    environment: environment,
                    session: session
                )
            },
            signInController: SaveMVPSignInControllerFactory.make(
                environment: environment,
                sessionStore: sessionStore
            ),
            authSession: sessionStore.load()
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if state.hasCompletedOnboarding {
                    kaiHome
                } else {
                    OnboardingView(
                        authSession: authSession,
                        isSupabaseConfigured: signInController != nil,
                        remoteSyncStatus: remoteSyncStatus,
                        showSignIn: {
                            isShowingSignIn = true
                        },
                        signOut: {
                            signOut()
                        },
                        syncNow: {
                            syncNow()
                        },
                        startDemo: {
                            updateState {
                                $0.startDemoSources(hasAccountSession: authSession != nil)
                            }
                        },
                        startReceiptOnly: {
                            updateState {
                                $0.completeOnboarding()
                            }
                        }
                    )
                }
            }
            .background(SAVETheme.canvas)
            .tint(SAVETheme.accent)
            .navigationTitle("SAVE")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        updateState {
                            $0.resetProgress()
                        }
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Reset progress")

                    if signInController != nil {
                        Menu {
                            if authSession == nil {
                                Button {
                                    isShowingSignIn = true
                                } label: {
                                    Label("Sign in or create account", systemImage: "person.crop.circle.badge.plus")
                                }
                            } else {
                                Button {
                                    syncNow()
                                } label: {
                                    Label("Sync now", systemImage: "arrow.trianglehead.2.clockwise")
                                }

                                Button(role: .destructive) {
                                    signOut()
                                } label: {
                                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                                }
                            }
                        } label: {
                            Label(authSession == nil ? "Account" : "Signed in", systemImage: authSession == nil ? "person.crop.circle.badge.plus" : "person.crop.circle.badge.checkmark")
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.light)
        .sheet(isPresented: $isShowingSignIn) {
            if let signInController {
                SupabaseSignInSheet(controller: signInController) { session in
                    handleSignedIn(session)
                }
                .presentationDetents([.medium])
            }
        }
        .task(id: authSession?.userID) {
            await restoreRemoteProgressIfAvailable()
            await loadAdministratorTemplatesIfAvailable()
            await loadGmailConnectionIfAvailable()
        }
        .onAppear {
            configureProgressStore()
        }
        .onOpenURL { url in
            handleGmailCallback(url)
        }
        .onChange(of: isShowingReceiptIntake) { _, isPresented in
            guard !isPresented,
                  let receiptID = pendingReviewReceiptID else {
                return
            }

            pendingReviewReceiptID = nil
            receiptReviewRoute = ReceiptReviewRoute(receiptID: receiptID)
        }
    }

    private var isGmailLive: Bool {
        state.isLiveConnected(.gmail, gmailConnection: liveGmailConnection)
    }

    private var kaiHome: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                AssistantHero(state: state, isGmailLive: isGmailLive) { source in
                    if source == .gmail {
                        if isGmailLive {
                            importGmailReceipts()
                        } else {
                            startGmailConnection()
                        }
                    } else {
                        updateState {
                            $0.connect(source)
                        }
                    }
                }
                if let gmailConnectionError {
                    Text(gmailConnectionError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 4)
                }
                GmailPrivacyView(
                    isConnected: isGmailLive,
                    lastScannedAt: gmailLastScannedAt,
                    isDisconnecting: isDisconnectingGmail,
                    disconnect: {
                        disconnectGmail()
                    }
                )
                AccountStatusView(
                    authSession: authSession,
                    isSupabaseConfigured: signInController != nil,
                    remoteSyncStatus: remoteSyncStatus,
                    showSignIn: {
                        isShowingSignIn = true
                    },
                    signOut: {
                        signOut()
                    },
                    syncNow: {
                        syncNow()
                    }
                )
                AssistantPromptBar {
                    isShowingReceiptIntake = true
                }
                ActiveTasksView(tasks: state.activeTasks) { task in
                    if task.startsGmailAuthorizationFlow {
                        startGmailConnection()
                    } else if task.id.hasPrefix("review-receipt-"), let receipt = state.firstNeedsReviewReceipt {
                        receiptReviewRoute = ReceiptReviewRoute(receiptID: receipt.id)
                    } else if task.id == "prepare-health-equity" {
                        updateState {
                            $0.perform(task)
                        }
                        if let packet = state.claimPackets.first(where: { $0.administratorName == "HealthEquity" }) {
                            claimPacketRoute = ClaimPacketRoute(packetID: packet.id)
                        }
                    } else if task.id == "export-tax-report" {
                        updateState {
                            $0.perform(task)
                        }
                        isShowingTaxExport = true
                    } else {
                        updateState {
                            $0.perform(task)
                        }
                    }
                }
                AssistantEvidenceView(
                    receipts: state.receipts,
                    taxExport: state.taxExport,
                    taxReportArtifact: state.taxReportArtifact,
                    reviewReceipt: { receipt in
                        receiptReviewRoute = ReceiptReviewRoute(receiptID: receipt.id)
                    }
                )
                AssistantCaseRail(claimPackets: state.claimPackets) { packet in
                    claimPacketRoute = ClaimPacketRoute(packetID: packet.id)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
        .background(SAVETheme.canvas)
        .sheet(isPresented: $isShowingReceiptIntake) {
            ReceiptIntakeSheet(
                importSampleReceipt: {
                    updateState {
                        try? $0.importSampleReceipt()
                    }
                    isShowingReceiptIntake = false
                    showLatestReceiptReview()
                },
                importImageReceipt: { image in
                    let draft = try await VisionReceiptOCRService().draft(from: image)
                    updateState {
                        $0.importReceiptDraft(draft)
                    }
                    isShowingReceiptIntake = false
                    showLatestReceiptReview()
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(item: $receiptReviewRoute) { route in
            if let receipt = state.receipts.first(where: { $0.id == route.receiptID }) {
                ReceiptReviewSheet(receipt: receipt) { lineItem, eligibility in
                    updateState {
                        $0.classifyLineItem(lineItem.id, as: eligibility)
                    }
                } editReceipt: { receipt, merchant, date in
                    updateState {
                        $0.editReceipt(receipt.id, merchant: merchant, date: date)
                    }
                } editLineItem: { lineItem, name, amount in
                    updateState {
                        $0.editLineItem(lineItem.id, name: name, amount: amount)
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .sheet(item: $claimPacketRoute) { route in
            if let packet = state.claimPackets.first(where: { $0.id == route.packetID }) {
                ClaimPacketDetailSheet(packet: packet, templates: administratorTemplates) { packet, submission in
                    updateState {
                        $0.submitClaimPacket(packet.id, submission: submission)
                    }
                } markReimbursed: { packet in
                    updateState {
                        $0.markClaimReimbursed(packet.id)
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $isShowingTaxExport) {
            TaxExportDetailSheet(export: state.taxExport)
                .presentationDetents([.medium, .large])
        }
    }

    private func updateState(_ mutate: (inout SaveMVPState) -> Void) {
        mutate(&state)
        progressStore.save(state.persisted)
    }

    private func handleSignedIn(_ session: SupabaseAuthSession) {
        authSession = session
        liveGmailConnection = nil
        configureProgressStore()
        hasAttemptedRemoteProgressLoad = false
        isShowingSignIn = false
    }

    private func signOut() {
        signInController?.signOut()
        authSession = nil
        liveGmailConnection = nil
        administratorTemplates = ClaimAdministratorTemplateLibrary.defaultTemplates
        remoteSyncStatus = nil
        hasAttemptedRemoteProgressLoad = false
        progressStore = UserDefaultsSaveMVPProgressStore()
        progressStore.save(state.persisted)
    }

    private func syncNow() {
        progressStore.save(state.persisted)
    }

    private func startGmailConnection() {
        gmailConnectionError = nil

        guard let authSession else {
            if signInController != nil {
                isShowingSignIn = true
            } else {
                updateState {
                    $0.connect(.gmail)
                }
            }
            return
        }

        guard let controller = gmailConnectionControllerFactory(authSession) else {
            updateState {
                $0.connect(.gmail)
            }
            return
        }

        isConnectingGmail = true
        Task {
            do {
                if let checker = gmailConfigurationCheckerFactory(authSession) {
                    let configuration = try await checker.check()
                    guard configuration.isConfigured else {
                        await MainActor.run {
                            isConnectingGmail = false
                            gmailConnectionError = gmailConfigurationErrorMessage(configuration)
                        }
                        return
                    }
                }

                let start = try await controller.startAuthorization()
                await MainActor.run {
                    pendingGmailAuthorizationStart = start
                    isConnectingGmail = false
                    openURL(start.authorizationURL)
                }
            } catch {
                await MainActor.run {
                    isConnectingGmail = false
                    gmailConnectionError = "Gmail connection could not start. Check Google OAuth configuration."
                }
            }
        }
    }

    private func handleGmailCallback(_ url: URL) {
        guard let callback = GmailOAuthCallback(url: url),
              let pendingGmailAuthorizationStart else {
            return
        }

        guard callback.state == pendingGmailAuthorizationStart.state else {
            gmailConnectionError = "Gmail connection returned an unexpected state. Try connecting again."
            self.pendingGmailAuthorizationStart = nil
            return
        }

        guard let authSession,
              let controller = gmailConnectionControllerFactory(authSession) else {
            gmailConnectionError = "Sign in again before completing Gmail."
            return
        }

        isConnectingGmail = true
        Task {
            do {
                _ = try await controller.completeAuthorization(
                    code: callback.code,
                    state: callback.state,
                    codeVerifier: pendingGmailAuthorizationStart.codeVerifier
                )
                await MainActor.run {
                    self.pendingGmailAuthorizationStart = nil
                    isConnectingGmail = false
                    updateState {
                        $0.connect(.gmail)
                    }
                }
                await loadGmailConnectionIfAvailable()
            } catch {
                await MainActor.run {
                    self.pendingGmailAuthorizationStart = nil
                    isConnectingGmail = false
                    gmailConnectionError = gmailErrorMessage(
                        for: error,
                        fallback: "Gmail connection could not finish. Check OAuth secrets and try again."
                    )
                }
            }
        }
    }

    private func importGmailReceipts() {
        gmailConnectionError = nil

        guard let authSession,
              let importer = gmailReceiptImporterFactory(authSession) else {
            gmailConnectionError = "Sign in and connect Gmail before scanning email receipts."
            return
        }

        isImportingGmail = true
        Task {
            do {
                if let checker = gmailConfigurationCheckerFactory(authSession) {
                    let configuration = try await checker.check()
                    guard configuration.isConfigured else {
                        await MainActor.run {
                            isImportingGmail = false
                            gmailConnectionError = gmailConfigurationErrorMessage(configuration)
                        }
                        return
                    }
                }

                let result = try await importer.importReceipts()
                await MainActor.run {
                    isImportingGmail = false
                    gmailLastScannedAt = Date()
                    gmailConnectionError = result.importedReceiptCount == 0
                        ? "Gmail scan finished. No new likely medical receipts found."
                        : "Gmail scan imported \(result.importedReceiptCount) likely medical receipt(s)."
                    hasAttemptedRemoteProgressLoad = false
                }
                await loadGmailConnectionIfAvailable()
                await restoreRemoteProgressIfAvailable()
            } catch {
                await MainActor.run {
                    isImportingGmail = false
                    gmailConnectionError = gmailErrorMessage(
                        for: error,
                        fallback: "Gmail scan could not run. Check Gmail OAuth secrets and connection status."
                    )
                }
            }
        }
    }

    private func disconnectGmail() {
        gmailConnectionError = nil

        guard state.connectedSources.contains(.gmail) else {
            return
        }

        guard let authSession,
              let disconnector = gmailDisconnectControllerFactory(authSession) else {
            updateState {
                $0.disconnect(.gmail)
            }
            gmailLastScannedAt = nil
            gmailConnectionError = "Gmail disconnected on this device."
            return
        }

        isDisconnectingGmail = true
        Task {
            do {
                _ = try await disconnector.disconnect()
                await MainActor.run {
                    isDisconnectingGmail = false
                    gmailLastScannedAt = nil
                    liveGmailConnection = nil
                    updateState {
                        $0.disconnect(.gmail)
                    }
                    gmailConnectionError = "Gmail disconnected. Kai will stop scanning email receipts."
                }
            } catch {
                await MainActor.run {
                    isDisconnectingGmail = false
                    gmailConnectionError = gmailErrorMessage(
                        for: error,
                        fallback: "Gmail could not be disconnected. Check connection and try again."
                    )
                }
            }
        }
    }

    private func gmailErrorMessage(for error: Error, fallback: String) -> String {
        if let authError = error as? SupabaseAuthError,
           case .serverMessage(let message) = authError {
            return "Gmail error: \(message)"
        }

        return fallback
    }

    private func gmailConfigurationErrorMessage(_ status: GmailConfigurationStatus) -> String {
        let missing = status.missing.isEmpty ? "unknown Gmail secret" : status.missing.joined(separator: ", ")
        return "Gmail V1 is not configured yet. Missing: \(missing)."
    }

    private func configureProgressStore() {
        progressStore = progressStoreFactory { status in
            handleRemoteSyncStatus(status)
        }
    }

    private func handleRemoteSyncStatus(_ status: SaveMVPRemoteSyncStatus) {
        Task { @MainActor in
            remoteSyncStatus = status
        }
    }

    private func restoreRemoteProgressIfAvailable() async {
        guard !hasAttemptedRemoteProgressLoad,
              let authSession else {
            return
        }

        hasAttemptedRemoteProgressLoad = true
        if let refreshedSession = await refreshAuthSessionIfNeeded(authSession) {
            self.authSession = refreshedSession
        }

        configureProgressStore()

        guard let activeSession = self.authSession,
              let loader = remoteProgressLoaderFactory(activeSession) else {
            progressStore.save(state.persisted)
            return
        }

        do {
            if let remoteState = try await loader.load() {
                state = SaveMVPState(persisted: remoteState)
                progressStore.save(remoteState)
            } else {
                progressStore.save(state.persisted)
            }
        } catch {
            return
        }
    }

    private func loadAdministratorTemplatesIfAvailable() async {
        guard let authSession,
              let loader = administratorTemplateLoaderFactory(authSession) else {
            administratorTemplates = ClaimAdministratorTemplateLibrary.defaultTemplates
            return
        }

        do {
            let templates = try await loader.load()
            if !templates.isEmpty {
                administratorTemplates = ClaimAdministratorTemplateLibrary.mergedWithDefaults(templates)
            }
        } catch {
            administratorTemplates = ClaimAdministratorTemplateLibrary.defaultTemplates
        }
    }

    private func loadGmailConnectionIfAvailable() async {
        guard let authSession,
              let loader = gmailConnectionLoaderFactory(authSession) else {
            liveGmailConnection = nil
            return
        }

        do {
            let connection = try await loader.load()
            await MainActor.run {
                liveGmailConnection = connection?.status == .connected ? connection : nil
                if connection?.status == .connected {
                    updateState {
                        $0.connect(.gmail)
                    }
                } else if state.connectedSources.contains(.gmail) {
                    updateState {
                        $0.disconnect(.gmail)
                    }
                }
            }
        } catch {
            await MainActor.run {
                liveGmailConnection = nil
                if state.connectedSources.contains(.gmail) {
                    updateState {
                        $0.disconnect(.gmail)
                    }
                }
            }
        }
    }

    private func refreshAuthSessionIfNeeded(_ session: SupabaseAuthSession) async -> SupabaseAuthSession? {
        guard !session.isUsable(),
              let signInController else {
            return session
        }

        return try? await signInController.refreshStoredSession()
    }

    private func showLatestReceiptReview() {
        guard let receipt = state.receipts.first else {
            return
        }

        pendingReviewReceiptID = receipt.id
    }
}

private struct ReceiptReviewRoute: Identifiable {
    let receiptID: UUID

    var id: UUID {
        receiptID
    }
}

private struct ClaimPacketRoute: Identifiable {
    let packetID: UUID

    var id: UUID {
        packetID
    }
}

private struct SupabaseSignInSheet: View {
    let controller: SaveMVPSignInController
    let onSignedIn: (SupabaseAuthSession) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var isSigningIn = false
    @State private var isCreatingAccount = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Auth mode", selection: $isCreatingAccount) {
                        Text("Sign in").tag(false)
                        Text("Create account").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if let successMessage {
                    Section {
                        Text(successMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .saveDocumentBackground()
            .navigationTitle(isCreatingAccount ? "Create account" : "Sign in")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(actionTitle) {
                        authenticate()
                    }
                    .disabled(email.isEmpty || password.isEmpty || isSigningIn)
                }
            }
        }
    }

    private var actionTitle: String {
        if isSigningIn {
            return isCreatingAccount ? "Creating" : "Signing in"
        }

        return isCreatingAccount ? "Create" : "Sign in"
    }

    private func authenticate() {
        errorMessage = nil
        successMessage = nil
        isSigningIn = true

        Task {
            do {
                let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                if isCreatingAccount {
                    let result = try await controller.signUp(email: trimmedEmail, password: password)
                    await MainActor.run {
                        isSigningIn = false
                        if let session = result.session {
                            onSignedIn(session)
                        } else {
                            successMessage = "Check your email to confirm the account, then sign in."
                        }
                    }
                    return
                }

                let session = try await controller.signIn(email: trimmedEmail, password: password)
                await MainActor.run {
                    isSigningIn = false
                    onSignedIn(session)
                }
            } catch {
                await MainActor.run {
                    isSigningIn = false
                    errorMessage = authErrorMessage(for: error, isCreatingAccount: isCreatingAccount)
                }
            }
        }
    }

    private func authErrorMessage(for error: Error, isCreatingAccount: Bool) -> String {
        if let authError = error as? SupabaseAuthError {
            switch authError {
            case .emailNotConfirmed:
                return "Confirm your email first, then sign in."
            case .serverMessage(let message):
                return message
            case .invalidURL, .missingUserID:
                break
            }
        }

        return isCreatingAccount
            ? "Account creation failed. Check the email and password."
            : "Sign in failed. Check the email and password."
    }
}

private struct OnboardingView: View {
    let authSession: SupabaseAuthSession?
    let isSupabaseConfigured: Bool
    let remoteSyncStatus: SaveMVPRemoteSyncStatus?
    let showSignIn: () -> Void
    let signOut: () -> Void
    let syncNow: () -> Void
    let startDemo: () -> Void
    let startReceiptOnly: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 12)

            SAVEIconBadge(symbol: "sparkles", size: 64)

            VStack(alignment: .leading, spacing: 10) {
                Text("Kai finds medical money you can claim back.")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(SAVETheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Start with demo Gmail discovery, or continue with receipt upload only. Live Gmail comes into V1; Plaid moves to V2.")
                    .font(.callout)
                    .foregroundStyle(SAVETheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            AccountStatusView(
                authSession: authSession,
                isSupabaseConfigured: isSupabaseConfigured,
                remoteSyncStatus: remoteSyncStatus,
                showSignIn: showSignIn,
                signOut: signOut,
                syncNow: syncNow
            )

            VStack(alignment: .leading, spacing: 12) {
                OnboardingPoint(symbol: "receipt.fill", title: "Receipts", detail: "Camera and gallery intake come first.")
                OnboardingPoint(symbol: "lock.shield.fill", title: "Privacy", detail: "Kai stores only what is needed for claims and tax backup.")
                OnboardingPoint(symbol: "doc.badge.arrow.up.fill", title: "Claims", detail: "V1 prepares guided HSA/FSA packets before live submission.")
            }

            Spacer()

            VStack(spacing: 10) {
                Button(action: startDemo) {
                    Text("Start with demo sources")
                }
                .buttonStyle(SAVEPrimaryButtonStyle())
                .accessibilityIdentifier("savePrimaryButton")

                Button(action: startReceiptOnly) {
                    Text("Continue receipt-only")
                }
                .buttonStyle(SAVESecondaryButtonStyle())
            }
        }
        .padding(22)
        .background(SAVETheme.canvas)
    }
}

private struct OnboardingPoint: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SAVEIconBadge(symbol: symbol, size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SAVETheme.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(SAVETheme.muted)
            }
        }
    }
}

private struct AssistantHero: View {
    let state: SaveMVPState
    let isGmailLive: Bool
    let connect: (ConnectedSource) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 12) {
                SAVEIconBadge(symbol: "sparkles", size: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Kai is working")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(SAVETheme.ink)
                    Text("Scanning receipts, finding email evidence, and preparing claims.")
                        .font(.subheadline)
                        .foregroundStyle(SAVETheme.muted)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Likely claimable")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(SAVETheme.muted)
                Text(state.summary.totalClaimable.currency)
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .foregroundStyle(SAVETheme.ink)
                    .minimumScaleFactor(0.65)
                Text(statusLine)
                    .font(.callout)
                    .foregroundStyle(SAVETheme.muted)
            }

            HStack(spacing: 10) {
                AssistantSourceButton(
                    title: "Gmail scan",
                    state: isGmailLive ? "live" : "off",
                    symbol: "envelope.fill",
                    isConnected: isGmailLive
                ) {
                    connect(.gmail)
                }
            }
        }
        .saveSolidSurface(cornerRadius: SAVETheme.largeSurfaceRadius, padding: 20)
    }

    private var statusLine: String {
        if !state.isReadyForEstimate {
            return "Connect Gmail or upload receipts to let Kai calculate the first claim-back estimate."
        }

        return state.summary.assistantStatusLine
    }
}

private struct GmailPrivacyView: View {
    let isConnected: Bool
    let lastScannedAt: Date?
    let isDisconnecting: Bool
    let disconnect: () -> Void

    var body: some View {
        if isConnected {
            HStack(alignment: .top, spacing: 12) {
                SAVEIconBadge(symbol: "lock.shield.fill", size: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Gmail receipt scan")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SAVETheme.ink)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(SAVETheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Button(isDisconnecting ? "Disconnecting" : "Disconnect") {
                    disconnect()
                }
                .buttonStyle(SAVECompactButtonStyle(tint: SAVETheme.muted))
                .disabled(isDisconnecting)
            }
            .saveSolidSurface(padding: 14)
        }
    }

    private var detail: String {
        let scanStatus = lastScannedAt.map { "Last scan \(formattedTime($0))." } ?? "No live scan has run on this device yet."
        return "\(scanStatus) Kai scans likely medical receipt and administrator messages, stores claim evidence, and stops scanning when Gmail is disconnected."
    }

    private func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

private struct AccountStatusView: View {
    let authSession: SupabaseAuthSession?
    let isSupabaseConfigured: Bool
    let remoteSyncStatus: SaveMVPRemoteSyncStatus?
    let showSignIn: () -> Void
    let signOut: () -> Void
    let syncNow: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            SAVEIconBadge(symbol: iconName, tint: iconColor, size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SAVETheme.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(SAVETheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if isSupabaseConfigured {
                if authSession == nil {
                    Button("Sign in") {
                        showSignIn()
                    }
                    .buttonStyle(SAVECompactButtonStyle(tint: SAVETheme.accent))
                } else {
                    VStack(spacing: 8) {
                        Button("Sync now") {
                            syncNow()
                        }
                        .buttonStyle(SAVECompactButtonStyle(tint: SAVETheme.accent))
                        .disabled(isSyncing)

                        Button("Sign out") {
                            signOut()
                        }
                        .buttonStyle(SAVECompactButtonStyle(tint: SAVETheme.muted))
                    }
                }
            }
        }
        .saveSolidSurface(padding: 14)
    }

    private var iconColor: Color {
        if !isSupabaseConfigured || authSession == nil {
            return .secondary
        }

        if case .failed = remoteSyncStatus {
            return SAVETheme.warning
        }

        return SAVETheme.accent
    }

    private var iconName: String {
        if !isSupabaseConfigured {
            return "icloud.slash"
        }

        if authSession == nil {
            return "person.crop.circle.badge.plus"
        }

        switch remoteSyncStatus {
        case .syncing:
            return "arrow.trianglehead.2.clockwise"
        case .synced:
            return "checkmark.icloud.fill"
        case .failed:
            return "exclamationmark.icloud.fill"
        case nil:
            return "checkmark.icloud.fill"
        }
    }

    private var title: String {
        if !isSupabaseConfigured {
            return "Local mode"
        }

        if authSession == nil {
            return "Not signed in"
        }

        switch remoteSyncStatus {
        case .syncing:
            return "Syncing"
        case .synced:
            return "Synced"
        case .failed:
            return "Sync needs retry"
        case nil:
            return "Signed in"
        }
    }

    private var detail: String {
        if !isSupabaseConfigured {
            return "Add Supabase environment values in the scheme to enable account sync."
        }

        guard authSession != nil else {
            return "Sign in or create an account to sync progress."
        }

        switch remoteSyncStatus {
        case .syncing(let date):
            return "Saving progress changes from \(formattedTime(date))."
        case .synced(let date):
            return "Last synced at \(formattedTime(date))."
        case .failed(let date):
            return "Last sync failed at \(formattedTime(date)). Check connection and retry."
        case nil:
            return "Progress sync is enabled for this device."
        }
    }

    private var isSyncing: Bool {
        if case .syncing = remoteSyncStatus {
            return true
        }

        return false
    }

    private func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

private struct AssistantPromptBar: View {
    let addReceipt: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: addReceipt) {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(SAVETheme.accent, in: Circle())
            }
            .accessibilityLabel("Add receipt")

            Text("Ask Kai or drop a receipt")
                .font(.body.weight(.medium))
                .foregroundStyle(SAVETheme.muted)

            Spacer()

            Image(systemName: "mic.fill")
                .foregroundStyle(SAVETheme.muted)
        }
        .padding(12)
        .saveGlassSurface(cornerRadius: SAVETheme.surfaceRadius, interactive: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("saveGlassCommandBar")
    }
}

private struct ReceiptIntakeSheet: View {
    let importSampleReceipt: () -> Void
    let importImageReceipt: (UIImage) async throws -> Void
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isShowingCamera = false
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        isShowingCamera = true
                    } else {
                        errorMessage = "Camera is not available in this simulator."
                    }
                } label: {
                    ReceiptIntakeOptionContent(
                        title: "Camera scan",
                        detail: "Capture a receipt and run Apple Vision OCR",
                        symbol: "camera.fill",
                        isEnabled: !isProcessing
                    )
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    ReceiptIntakeOptionContent(
                        title: "Photo library",
                        detail: "Choose a receipt and run Apple Vision OCR",
                        symbol: "photo.on.rectangle.angled",
                        isEnabled: !isProcessing
                    )
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)

                ReceiptIntakeOption(
                    title: "Use sample receipt",
                    detail: "Imports a CVS receipt through the OCR parser",
                    symbol: "text.viewfinder",
                    isEnabled: true,
                    action: importSampleReceipt
                )
                .disabled(isProcessing)

                if isProcessing {
                    Label("Kai is reading the receipt", systemImage: "text.viewfinder")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SAVETheme.accent)
                        .padding(.top, 4)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(18)
            .background(SAVETheme.canvas)
            .navigationTitle("Add receipt")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: selectedPhotoItem) { _, item in
                guard let item else {
                    return
                }

                Task {
                    await importPhotoItem(item)
                }
            }
            .sheet(isPresented: $isShowingCamera) {
                ReceiptCameraPicker(
                    didCapture: { image in
                        isShowingCamera = false
                        Task {
                            await importImage(image)
                        }
                    },
                    didCancel: {
                        isShowingCamera = false
                    }
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("saveReceiptIntakeSheet")
    }

    private func importPhotoItem(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = "Kai couldn't load that image."
                return
            }

            await importImage(image)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importImage(_ image: UIImage) async {
        isProcessing = true
        errorMessage = nil
        defer {
            isProcessing = false
            selectedPhotoItem = nil
        }

        do {
            try await importImageReceipt(image)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ReceiptIntakeOption: View {
    let title: String
    let detail: String
    let symbol: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ReceiptIntakeOptionContent(
                title: title,
                detail: detail,
                symbol: symbol,
                isEnabled: isEnabled
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private struct ReceiptIntakeOptionContent: View {
    let title: String
    let detail: String
    let symbol: String
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            SAVEIconBadge(
                symbol: symbol,
                tint: isEnabled ? SAVETheme.accent : SAVETheme.muted,
                size: 38
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SAVETheme.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(SAVETheme.muted)
            }

            Spacer()
        }
        .saveSolidSurface(padding: 14)
    }
}

private struct ActiveTasksView: View {
    let tasks: [MVPTask]
    let perform: (MVPTask) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SAVESectionTitle(title: "Active tasks")

            if tasks.isEmpty {
                AssistantDoneCard()
            } else {
                ForEach(tasks) { task in
                    AssistantTaskCard(task: task, tint: tint(for: task)) {
                        perform(task)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("saveTaskLedger")
    }

    private func tint(for task: MVPTask) -> Color {
        switch task.id {
        case "connect-gmail", "link-bank", "prepare-health-equity":
            return SAVETheme.accent
        case let taskID where taskID.hasPrefix("review-receipt-"):
            return SAVETheme.warning
        case "export-tax-report":
            return SAVETheme.accent
        default:
            return SAVETheme.accent
        }
    }
}

private struct AssistantTaskCard: View {
    let task: MVPTask
    let tint: Color
    let perform: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                SAVEIconBadge(symbol: task.symbol, tint: tint, size: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SAVETheme.ink)
                    Text(task.detail)
                        .font(.caption)
                        .foregroundStyle(SAVETheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if let amount = task.amount {
                    Text(amount.currency)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(tint)
                }
            }

            Button(action: perform) {
                Text(task.actionTitle)
            }
            .buttonStyle(SAVEPrimaryButtonStyle())
        }
        .saveSolidSurface(padding: 14)
    }
}

private struct AssistantDoneCard: View {
    var body: some View {
        Label("Kai has no open tasks", systemImage: "checkmark.seal.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(SAVETheme.success)
            .frame(maxWidth: .infinity, alignment: .leading)
            .saveSolidSurface(padding: 14)
    }
}

private struct AssistantEvidenceView: View {
    let receipts: [Receipt]
    let taxExport: TaxExport
    let taxReportArtifact: TaxReportArtifact?
    let reviewReceipt: (Receipt) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SAVESectionTitle(title: "Evidence")

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    AssistantMetricCard(value: "\(receipts.count)", label: "receipts", symbol: "receipt.fill")
                    Rectangle().fill(SAVETheme.hairline).frame(width: 0.5, height: 46)
                    AssistantMetricCard(value: "\(taxExport.csvRows.count)", label: "tax rows", symbol: "doc.text.fill")
                }

                if let taxReportArtifact {
                    SAVELedgerDivider()
                    Label(
                        "\(taxReportArtifact.filename) exported",
                        systemImage: "square.and.arrow.down.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SAVETheme.accent)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(receipts.prefix(2)) { receipt in
                    SAVELedgerDivider()
                    Button {
                        reviewReceipt(receipt)
                    } label: {
                        HStack(spacing: 12) {
                            SAVEIconBadge(
                                symbol: receipt.source == .bank ? "building.columns.fill" : "receipt.fill",
                                size: 34
                            )

                            VStack(alignment: .leading, spacing: 3) {
                                Text(receipt.merchant)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(SAVETheme.ink)
                                Text("\(receipt.source.rawValue) matched \(receipt.lineItems.count) line items")
                                    .font(.caption)
                                    .foregroundStyle(SAVETheme.muted)
                            }

                            Spacer()

                            Text(receipt.reimbursableTotal.currency)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(SAVETheme.ink)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(SAVETheme.muted)
                        }
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .saveSolidSurface(padding: 14)
        }
    }
}

private struct ReceiptReviewSheet: View {
    let receipt: Receipt
    let classify: (ReceiptLineItem, Eligibility) -> Void
    let editReceipt: (Receipt, String, Date) -> Void
    let editLineItem: (ReceiptLineItem, String, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isEditingReceipt = false
    @State private var editingLineItem: ReceiptLineItem?

    var body: some View {
        NavigationStack {
            List {
                Section("Receipt") {
                    LabeledContent("Merchant", value: receipt.merchant)
                    LabeledContent("Source", value: receipt.source.rawValue)
                    LabeledContent("Total", value: receipt.total.currency)
                    LabeledContent("Review", value: reviewStatus)
                    Button {
                        isEditingReceipt = true
                    } label: {
                        Label("Edit receipt", systemImage: "pencil")
                    }
                }

                Section("Line items") {
                    ForEach(receipt.lineItems) { item in
                        LineItemReviewCard(item: item) { eligibility in
                            classify(item, eligibility)
                        } edit: {
                            editingLineItem = item
                        }
                    }
                }
            }
            .saveDocumentBackground()
            .navigationTitle("Review receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .disabled(receipt.hasNeedsReviewItem)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("saveReceiptReviewSheet")
        .sheet(isPresented: $isEditingReceipt) {
            ReceiptEditSheet(receipt: receipt) { merchant, date in
                editReceipt(receipt, merchant, date)
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $editingLineItem) { item in
            LineItemEditSheet(item: item) { name, amount in
                editLineItem(item, name, amount)
            }
            .presentationDetents([.medium])
        }
    }

    private var reviewStatus: String {
        let remainingCount = receipt.lineItems.filter { $0.eligibility == .needsReview }.count
        if remainingCount == 0 {
            return "Ready"
        }

        return "\(remainingCount) left"
    }
}

private struct ReceiptEditSheet: View {
    let receipt: Receipt
    let save: (String, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var merchant: String
    @State private var date: Date

    init(receipt: Receipt, save: @escaping (String, Date) -> Void) {
        self.receipt = receipt
        self.save = save
        _merchant = State(initialValue: receipt.merchant)
        _date = State(initialValue: receipt.date)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Receipt") {
                    TextField("Merchant", text: $merchant)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
            }
            .saveDocumentBackground()
            .navigationTitle("Edit receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(merchant, date)
                        dismiss()
                    }
                    .disabled(merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct LineItemEditSheet: View {
    let item: ReceiptLineItem
    let save: (String, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var amount: String

    init(item: ReceiptLineItem, save: @escaping (String, Double) -> Void) {
        self.item = item
        self.save = save
        _name = State(initialValue: item.name)
        _amount = State(initialValue: String(format: "%.2f", item.amount))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Line item") {
                    TextField("Name", text: $name)
                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                }
            }
            .saveDocumentBackground()
            .navigationTitle("Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let parsedAmount {
                            save(name, parsedAmount)
                            dismiss()
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && parsedAmount != nil
    }

    private var parsedAmount: Double? {
        let cleanedAmount = amount.replacingOccurrences(of: "$", with: "")
        guard let value = Double(cleanedAmount), value >= 0 else {
            return nil
        }

        return value
    }
}

private struct LineItemReviewCard: View {
    let item: ReceiptLineItem
    let classify: (Eligibility) -> Void
    let edit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                    Label(item.eligibility.rawValue, systemImage: item.eligibility.symbolName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                }

                Spacer()

                HStack(spacing: 8) {
                    Text(item.amount.currency)
                        .font(.subheadline.weight(.bold))
                    Button(action: edit) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Edit \(item.name)")
                }
            }

            if item.eligibility == .needsReview {
                HStack(spacing: 8) {
                    ReviewChoiceButton(title: "FSA", tint: SAVETheme.accent) {
                        classify(.fsaEligible)
                    }
                    ReviewChoiceButton(title: "HSA", tint: SAVETheme.accent) {
                        classify(.hsaEligible)
                    }
                    ReviewChoiceButton(title: "Tax", tint: SAVETheme.accent) {
                        classify(.scheduleADeductible)
                    }
                    ReviewChoiceButton(title: "Exclude", tint: .secondary) {
                        classify(.notEligible)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var tint: Color {
        switch item.eligibility {
        case .fsaEligible, .hsaEligible:
            return SAVETheme.success
        case .scheduleADeductible:
            return SAVETheme.accent
        case .notEligible:
            return .secondary
        case .needsReview:
            return SAVETheme.warning
        }
    }
}

private struct ReviewChoiceButton: View {
    let title: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SAVECompactButtonStyle(tint: tint))
    }
}

private struct AssistantMetricCard: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(SAVETheme.accent)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(SAVETheme.ink)
            Text(label)
                .font(.caption)
                .foregroundStyle(SAVETheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

private struct AssistantCaseRail: View {
    let claimPackets: [ClaimPacket]
    let openPacket: (ClaimPacket) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SAVESectionTitle(title: "Claims")

            VStack(spacing: 0) {
                ForEach(claimPackets) { packet in
                    Button {
                        openPacket(packet)
                    } label: {
                        HStack(spacing: 12) {
                            SAVEIconBadge(symbol: "doc.text.fill", size: 36)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(packet.administratorName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(SAVETheme.ink)
                                Text("\(packet.submissionMode.rawValue) - \(packet.status.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(SAVETheme.muted)
                            }

                            Spacer()

                            Text(packet.total.currency)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(SAVETheme.ink)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(SAVETheme.muted)
                        }
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    SAVELedgerDivider()
                }
            }
            .saveSolidSurface(padding: 14)
        }
    }
}

private struct ClaimPacketDetailSheet: View {
    let packet: ClaimPacket
    let templates: [ClaimAdministratorTemplate]
    let submit: (ClaimPacket, ClaimSubmission) -> Void
    let markReimbursed: (ClaimPacket) -> Void
    @State private var pdfURL: URL?
    @State private var errorMessage: String?
    @State private var submissionMethod: ClaimSubmissionMethod = .administratorPortal
    @State private var confirmationNumber = ""
    @State private var submissionNotes = ""

    private var document: ClaimPacketDocument {
        ClaimPacketDocumentBuilder(templates: templates).build(from: packet)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Packet") {
                    LabeledContent("Administrator", value: packet.administratorName)
                    LabeledContent("Mode", value: packet.submissionMode.rawValue)
                    LabeledContent("Status", value: packet.status.rawValue)
                    LabeledContent("Total", value: packet.total.currency)
                    ClaimProgressRail(status: packet.status)
                }

                Section("Administrator template") {
                    LabeledContent("Version", value: document.template.version)
                    LabeledContent("Supported mode", value: document.template.supportedSubmissionMode.rawValue)
                    ForEach(document.template.requiredFields, id: \.self) { field in
                        Label(field, systemImage: "text.badge.checkmark")
                    }
                    ForEach(document.template.evidenceRequirements, id: \.self) { requirement in
                        Label(requirement, systemImage: "doc.text.magnifyingglass")
                    }
                }

                Section("Submission checklist") {
                    ForEach(Array(document.template.submissionChecklist.enumerated()), id: \.element) { index, step in
                        Label(step, systemImage: "\(index + 1).circle.fill")
                    }
                }

                Section("Evidence") {
                    ForEach(packet.lineItems) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.eligibility.symbolName)
                                .foregroundStyle(SAVETheme.success)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.subheadline.weight(.semibold))
                                Text(item.eligibility.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(item.amount.currency)
                                .font(.subheadline.weight(.bold))
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Claim packet PDF") {
                    ClaimDocumentPreview(packet: packet, version: document.template.version)

                    if let pdfURL {
                        ShareLink(item: pdfURL) {
                            Label("Share claim packet", systemImage: "square.and.arrow.up.fill")
                        }
                        .buttonStyle(SAVEPrimaryButtonStyle())
                    } else {
                        Button {
                            writePDF()
                        } label: {
                            Label("Generate PDF", systemImage: "doc.richtext.fill")
                        }
                        .buttonStyle(SAVEPrimaryButtonStyle())
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Submission tracking") {
                    switch packet.status {
                    case .ready:
                        Picker("Method", selection: $submissionMethod) {
                            ForEach(ClaimSubmissionMethod.allCases) { method in
                                Text(method.rawValue).tag(method)
                            }
                        }
                        TextField("Confirmation number", text: $confirmationNumber)
                            .textInputAutocapitalization(.characters)
                        TextField("Notes", text: $submissionNotes, axis: .vertical)
                            .lineLimit(2...4)
                        Button {
                            submit(packet, currentSubmission)
                        } label: {
                            Label("Mark submitted", systemImage: "paperplane.fill")
                        }
                        .buttonStyle(SAVESecondaryButtonStyle())
                    case .submittedByUser:
                        if let submission = packet.submission {
                            LabeledContent("Method", value: submission.method.rawValue)
                            LabeledContent("Confirmation", value: submission.confirmationNumber.isEmpty ? "Not recorded" : submission.confirmationNumber)
                            if !submission.notes.isEmpty {
                                Text(submission.notes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Label("Kai is tracking reimbursement status", systemImage: "clock.badge.checkmark.fill")
                            .foregroundStyle(.secondary)
                        Button {
                            markReimbursed(packet)
                        } label: {
                            Label("Mark reimbursed", systemImage: "checkmark.circle.fill")
                        }
                        .buttonStyle(SAVEPrimaryButtonStyle())
                    case .reimbursed:
                        Label("Reimbursement recorded", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.secondary)
                    default:
                        Label("Prepare the claim packet before tracking submission", systemImage: "doc.badge.clock.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .saveDocumentBackground()
            .navigationTitle("Claim packet")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if pdfURL == nil {
                    writePDF()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("saveClaimPacketSheet")
    }

    private var currentSubmission: ClaimSubmission {
        ClaimSubmission(
            submittedAt: Date(),
            method: submissionMethod,
            confirmationNumber: confirmationNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: submissionNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func writePDF() {
        do {
            let data = ClaimPacketPDFRenderer().render(document)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("save-claim-packets", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(document.filename)
            try data.write(to: url, options: .atomic)
            pdfURL = url
            errorMessage = nil
        } catch {
            errorMessage = "Kai could not generate this PDF."
        }
    }
}

private struct ClaimProgressRail: View {
    let status: ClaimStatus

    private let steps = ["Evidence", "Packet", "Submit", "Track"]

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(SAVETheme.hairline)
                .frame(height: 1)
                .padding(.horizontal, 34)
                .offset(y: 14)

            HStack(spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, title in
                    VStack(spacing: 6) {
                        Image(systemName: symbol(for: index))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(tint(for: index))
                            .frame(width: 28, height: 28)
                            .background(SAVETheme.surface, in: Circle())
                            .overlay {
                                Circle().stroke(tint(for: index).opacity(0.22), lineWidth: 1)
                            }
                        Text(title)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(index <= currentStep ? SAVETheme.ink : SAVETheme.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var currentStep: Int {
        switch status {
        case .draft:
            return 0
        case .ready, .rejected, .needsAction:
            return 2
        case .submittedByUser, .submittedInApp:
            return 3
        case .reimbursed:
            return 4
        }
    }

    private func symbol(for index: Int) -> String {
        index < currentStep || status == .reimbursed ? "checkmark" : "circle.fill"
    }

    private func tint(for index: Int) -> Color {
        if index < currentStep || status == .reimbursed {
            return SAVETheme.success
        }
        if index == currentStep {
            return SAVETheme.accent
        }
        return SAVETheme.muted
    }
}

private struct ClaimDocumentPreview: View {
    let packet: ClaimPacket
    let version: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("HSA/FSA reimbursement claim")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SAVETheme.ink)
                    Text("Administrator template \(version)")
                        .font(.caption)
                        .foregroundStyle(SAVETheme.muted)
                }
                Spacer()
                SAVEIconBadge(symbol: "doc.text.fill", size: 34)
            }

            SAVELedgerDivider()

            HStack {
                previewValue("Administrator", packet.administratorName)
                previewValue("Items", "\(packet.lineItems.count)")
                previewValue("Total", packet.total.currency)
            }
        }
        .saveSolidSurface(cornerRadius: SAVETheme.controlRadius, padding: 14)
    }

    private func previewValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(SAVETheme.muted)
                .textCase(.uppercase)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SAVETheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TaxDocumentPreview: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            SAVEIconBadge(symbol: symbol, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SAVETheme.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(SAVETheme.muted)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(SAVETheme.success)
        }
        .saveSolidSurface(cornerRadius: SAVETheme.controlRadius, padding: 14)
    }
}

private struct TaxExportDetailSheet: View {
    let export: TaxExport
    @State private var csvURL: URL?
    @State private var pdfURL: URL?
    @State private var errorMessage: String?

    private var document: TaxExportDocument {
        TaxExportDocumentBuilder().build(from: export)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Schedule A export") {
                    LabeledContent("Year", value: "\(export.year)")
                    LabeledContent("Rows", value: "\(export.rows.count)")
                    LabeledContent("Total", value: export.totalMedicalExpenses.currency)
                }

                Section("CSV") {
                    TaxDocumentPreview(
                        title: "Medical expense data",
                        subtitle: "\(export.rows.count) itemized rows",
                        symbol: "tablecells.fill"
                    )

                    if let csvURL {
                        ShareLink(item: csvURL) {
                            Label("Share CSV", systemImage: "tablecells.fill")
                        }
                        .buttonStyle(SAVESecondaryButtonStyle())
                    }
                }

                Section("PDF report") {
                    TaxDocumentPreview(
                        title: "Schedule A medical report",
                        subtitle: export.totalMedicalExpenses.currency,
                        symbol: "doc.richtext.fill"
                    )

                    if let pdfURL {
                        ShareLink(item: pdfURL) {
                            Label("Share PDF", systemImage: "square.and.arrow.up.fill")
                        }
                        .buttonStyle(SAVEPrimaryButtonStyle())
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .saveDocumentBackground()
            .navigationTitle("Tax export")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if csvURL == nil || pdfURL == nil {
                    writeFiles()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("saveTaxExportSheet")
    }

    private func writeFiles() {
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("save-tax-exports", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let csvFileURL = directory.appendingPathComponent(document.csvFilename)
            try document.csvText.data(using: .utf8)?.write(to: csvFileURL, options: .atomic)

            let pdfFileURL = directory.appendingPathComponent(document.pdfFilename)
            let pdfData = TaxExportPDFRenderer().render(document)
            try pdfData.write(to: pdfFileURL, options: .atomic)

            csvURL = csvFileURL
            pdfURL = pdfFileURL
            errorMessage = nil
        } catch {
            errorMessage = "Kai could not generate the tax export files."
        }
    }
}

private struct AssistantSourceButton: View {
    let title: String
    let state: String
    let symbol: String
    let isConnected: Bool
    let connect: () -> Void

    var body: some View {
        Button(action: connect) {
            Label("\(title): \(state)", systemImage: symbol)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .foregroundStyle(isConnected ? SAVETheme.accent : SAVETheme.muted)
                .background((isConnected ? SAVETheme.accent : SAVETheme.muted).opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AssistantNativeContentView()
}
