import PhotosUI
import SwiftUI
import UIKit

struct AssistantNativeContentView: View {
    private let progressStoreFactory: () -> SaveMVPProgressStoring
    private let remoteProgressLoaderFactory: (SupabaseAuthSession) -> SaveMVPRemoteProgressLoading?
    private let signInController: SaveMVPSignInController?
    @State private var progressStore: SaveMVPProgressStoring
    @State private var state: SaveMVPState
    @State private var authSession: SupabaseAuthSession?
    @State private var hasAttemptedRemoteProgressLoad = false
    @State private var isShowingSignIn = false
    @State private var isShowingReceiptIntake = false
    @State private var receiptReviewRoute: ReceiptReviewRoute?
    @State private var pendingReviewReceiptID: UUID?
    @State private var claimPacketRoute: ClaimPacketRoute?
    @State private var isShowingTaxExport = false

    init(
        progressStore: SaveMVPProgressStoring = UserDefaultsSaveMVPProgressStore(),
        progressStoreFactory: (() -> SaveMVPProgressStoring)? = nil,
        remoteProgressLoaderFactory: @escaping (SupabaseAuthSession) -> SaveMVPRemoteProgressLoading? = { _ in nil },
        signInController: SaveMVPSignInController? = nil,
        authSession: SupabaseAuthSession? = nil
    ) {
        self.progressStoreFactory = progressStoreFactory ?? { progressStore }
        self.remoteProgressLoaderFactory = remoteProgressLoaderFactory
        self.signInController = signInController
        if ProcessInfo.processInfo.arguments.contains("RESET_SAVE_MVP_PROGRESS") {
            progressStore.save(SaveMVPPersistedState())
        }
        _progressStore = State(initialValue: progressStore)
        _state = State(initialValue: SaveMVPState(persisted: progressStore.load()))
        _authSession = State(initialValue: authSession)
    }

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        sessionStore: SupabaseAuthSessionStoring = UserDefaultsSupabaseAuthSessionStore()
    ) {
        let makeProgressStore = {
            SaveMVPProgressStoreFactory.make(
                environment: environment,
                sessionStore: sessionStore
            )
        }
        let progressStore = makeProgressStore()
        self.init(
            progressStore: progressStore,
            progressStoreFactory: makeProgressStore,
            remoteProgressLoaderFactory: { session in
                SaveMVPRemoteProgressLoaderFactory.make(
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
                        showSignIn: {
                            isShowingSignIn = true
                        },
                        signOut: {
                            signOut()
                        },
                        startDemo: {
                            updateState {
                                $0.completeOnboarding()
                                $0.connect(.gmail)
                                $0.connect(.bank)
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
            .background(AssistantTheme.background)
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

    private var kaiHome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                AssistantHero(state: state) { source in
                    updateState {
                        $0.connect(source)
                    }
                }
                AccountStatusView(
                    authSession: authSession,
                    isSupabaseConfigured: signInController != nil,
                    showSignIn: {
                        isShowingSignIn = true
                    },
                    signOut: {
                        signOut()
                    }
                )
                AssistantPromptBar {
                    isShowingReceiptIntake = true
                }
                ActiveTasksView(tasks: state.activeTasks) { task in
                    if task.id.hasPrefix("review-receipt-"), let receipt = state.firstNeedsReviewReceipt {
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
            .padding(.vertical, 20)
        }
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
                ClaimPacketDetailSheet(packet: packet) { packet in
                    updateState {
                        $0.submitClaimPacket(packet.id)
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
        progressStore = progressStoreFactory()
        hasAttemptedRemoteProgressLoad = false
        isShowingSignIn = false
    }

    private func signOut() {
        signInController?.signOut()
        authSession = nil
        hasAttemptedRemoteProgressLoad = false
        progressStore = UserDefaultsSaveMVPProgressStore()
        progressStore.save(state.persisted)
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

        progressStore = progressStoreFactory()

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
                    errorMessage = isCreatingAccount
                        ? "Account creation failed. Check the email and password."
                        : "Sign in failed. Check the email and password."
                }
            }
        }
    }
}

private struct OnboardingView: View {
    let authSession: SupabaseAuthSession?
    let isSupabaseConfigured: Bool
    let showSignIn: () -> Void
    let signOut: () -> Void
    let startDemo: () -> Void
    let startReceiptOnly: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 18)

            ZStack {
                Circle()
                    .fill(.teal.gradient)
                Image(systemName: "sparkles")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 10) {
                Text("Kai finds medical money you can claim back.")
                    .font(.largeTitle.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Start with demo Gmail and bank sources, or continue with receipt upload only. Live integrations come after the claim and export loop is solid.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            AccountStatusView(
                authSession: authSession,
                isSupabaseConfigured: isSupabaseConfigured,
                showSignIn: showSignIn,
                signOut: signOut
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
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)

                Button(action: startReceiptOnly) {
                    Text("Continue receipt-only")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(22)
    }
}

private struct OnboardingPoint: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.teal)
                .frame(width: 32, height: 32)
                .background(.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AssistantHero: View {
    let state: SaveMVPState
    let connect: (ConnectedSource) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.teal.gradient)
                    Image(systemName: "sparkles")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Kai is working")
                        .font(.title2.weight(.bold))
                    Text("Scanning receipts, matching bank charges, and preparing claims.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Recoverable now")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text(state.summary.totalClaimable.currency)
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.65)
                Text(statusLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                AssistantSourceButton(
                    title: "Gmail scan",
                    state: state.connectedSources.contains(.gmail) ? "live" : "off",
                    symbol: "envelope.fill",
                    isConnected: state.connectedSources.contains(.gmail)
                ) {
                    connect(.gmail)
                }
                AssistantSourceButton(
                    title: "Bank match",
                    state: state.connectedSources.contains(.bank) ? "on" : "off",
                    symbol: "building.columns.fill",
                    isConnected: state.connectedSources.contains(.bank)
                ) {
                    connect(.bank)
                }
            }
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var statusLine: String {
        if !state.isReadyForEstimate {
            return "Connect Gmail and bank to let Kai calculate the first claim-back estimate."
        }

        return "\(state.summary.readyClaimCount) claim packets found. \(state.summary.needsReviewCount) item needs your review before Kai includes it."
    }
}

private struct AccountStatusView: View {
    let authSession: SupabaseAuthSession?
    let isSupabaseConfigured: Bool
    let showSignIn: () -> Void
    let signOut: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.headline)
                .foregroundStyle(authSession == nil ? Color.secondary : Color.teal)
                .frame(width: 34, height: 34)
                .background((authSession == nil ? Color.secondary : Color.teal).opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if isSupabaseConfigured {
                Button(authSession == nil ? "Sign in" : "Sign out") {
                    if authSession == nil {
                        showSignIn()
                    } else {
                        signOut()
                    }
                }
                .buttonStyle(.bordered)
                .tint(authSession == nil ? .teal : .secondary)
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var iconName: String {
        if !isSupabaseConfigured {
            return "icloud.slash"
        }

        return authSession == nil ? "person.crop.circle.badge.plus" : "checkmark.icloud.fill"
    }

    private var title: String {
        if !isSupabaseConfigured {
            return "Local mode"
        }

        return authSession == nil ? "Not signed in" : "Signed in"
    }

    private var detail: String {
        if !isSupabaseConfigured {
            return "Add Supabase environment values in the scheme to enable account sync."
        }

        return authSession == nil
            ? "Sign in or create an account to sync progress."
            : "Progress sync is enabled for this device."
    }
}

private struct AssistantPromptBar: View {
    let addReceipt: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: addReceipt) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.teal)
            }
            .accessibilityLabel("Add receipt")

            Text("Ask Kai or drop a receipt")
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer()

            Image(systemName: "mic.fill")
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                        .foregroundStyle(.teal)
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
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(isEnabled ? .teal : .secondary)
                .frame(width: 38, height: 38)
                .background((isEnabled ? Color.teal : Color.secondary).opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ActiveTasksView: View {
    let tasks: [MVPTask]
    let perform: (MVPTask) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active tasks")
                .font(.headline)

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
    }

    private func tint(for task: MVPTask) -> Color {
        switch task.id {
        case "connect-gmail", "link-bank", "prepare-health-equity":
            return .teal
        case let taskID where taskID.hasPrefix("review-receipt-"):
            return .orange
        case "export-tax-report":
            return .blue
        default:
            return .teal
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
                Image(systemName: task.symbol)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.subheadline.weight(.semibold))
                    Text(task.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct AssistantDoneCard: View {
    var body: some View {
        Label("Kai has no open tasks", systemImage: "checkmark.seal.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.teal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct AssistantEvidenceView: View {
    let receipts: [Receipt]
    let taxExport: TaxExport
    let taxReportArtifact: TaxReportArtifact?
    let reviewReceipt: (Receipt) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kai's evidence")
                .font(.headline)

            HStack(spacing: 12) {
                AssistantMetricCard(value: "\(receipts.count)", label: "receipts reviewed", symbol: "receipt.fill")
                AssistantMetricCard(value: "\(taxExport.csvRows.count)", label: "tax rows ready", symbol: "doc.text.fill")
            }

            if let taxReportArtifact {
                Label(
                    "\(taxReportArtifact.filename) exported",
                    systemImage: "square.and.arrow.down.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.blue.opacity(0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            ForEach(receipts.prefix(2)) { receipt in
                Button {
                    reviewReceipt(receipt)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: receipt.source == .bank ? "building.columns.fill" : "receipt.fill")
                            .foregroundStyle(.teal)
                            .frame(width: 34, height: 34)
                            .background(.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(receipt.merchant)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("\(receipt.source.rawValue) matched \(receipt.lineItems.count) line items")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(receipt.reimbursableTotal.currency)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.teal)
                    }
                }
                .buttonStyle(.plain)
                .padding(12)
                .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
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
                    ReviewChoiceButton(title: "FSA", tint: .teal) {
                        classify(.fsaEligible)
                    }
                    ReviewChoiceButton(title: "HSA", tint: .teal) {
                        classify(.hsaEligible)
                    }
                    ReviewChoiceButton(title: "Tax", tint: .blue) {
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
            return .teal
        case .scheduleADeductible:
            return .blue
        case .notEligible:
            return .secondary
        case .needsReview:
            return .orange
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
        .buttonStyle(.bordered)
        .tint(tint)
    }
}

private struct AssistantMetricCard: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.teal)
            Text(value)
                .font(.title3.weight(.bold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct AssistantCaseRail: View {
    let claimPackets: [ClaimPacket]
    let openPacket: (ClaimPacket) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cases Kai is moving")
                .font(.headline)

            ForEach(claimPackets) { packet in
                Button {
                    openPacket(packet)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(packet.administratorName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("\(packet.submissionMode.rawValue) - \(packet.status.rawValue)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(packet.total.currency)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)
                .padding(14)
                .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
}

private struct ClaimPacketDetailSheet: View {
    let packet: ClaimPacket
    let submit: (ClaimPacket) -> Void
    let markReimbursed: (ClaimPacket) -> Void
    @State private var pdfURL: URL?
    @State private var errorMessage: String?

    private var document: ClaimPacketDocument {
        ClaimPacketDocumentBuilder().build(from: packet)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Packet") {
                    LabeledContent("Administrator", value: packet.administratorName)
                    LabeledContent("Mode", value: packet.submissionMode.rawValue)
                    LabeledContent("Status", value: packet.status.rawValue)
                    LabeledContent("Total", value: packet.total.currency)
                }

                Section("Evidence") {
                    ForEach(packet.lineItems) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.eligibility.symbolName)
                                .foregroundStyle(.teal)
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
                    Text(document.text)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    if let pdfURL {
                        ShareLink(item: pdfURL) {
                            Label("Share PDF", systemImage: "square.and.arrow.up.fill")
                        }
                    } else {
                        Button {
                            writePDF()
                        } label: {
                            Label("Generate PDF", systemImage: "doc.richtext.fill")
                        }
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
                        Button {
                            submit(packet)
                        } label: {
                            Label("Mark submitted by user", systemImage: "paperplane.fill")
                        }
                    case .submittedByUser:
                        Label("Kai is tracking reimbursement status", systemImage: "clock.badge.checkmark.fill")
                            .foregroundStyle(.secondary)
                        Button {
                            markReimbursed(packet)
                        } label: {
                            Label("Mark reimbursed", systemImage: "checkmark.circle.fill")
                        }
                    case .reimbursed:
                        Label("Reimbursement recorded", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.secondary)
                    default:
                        Label("Prepare the claim packet before tracking submission", systemImage: "doc.badge.clock.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Claim packet")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if pdfURL == nil {
                    writePDF()
                }
            }
        }
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
                    Text(document.csvText)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    if let csvURL {
                        ShareLink(item: csvURL) {
                            Label("Share CSV", systemImage: "tablecells.fill")
                        }
                    }
                }

                Section("PDF report") {
                    Text(document.reportText)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    if let pdfURL {
                        ShareLink(item: pdfURL) {
                            Label("Share PDF", systemImage: "square.and.arrow.up.fill")
                        }
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
            .navigationTitle("Tax export")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if csvURL == nil || pdfURL == nil {
                    writeFiles()
                }
            }
        }
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
                .foregroundStyle(isConnected ? .teal : .secondary)
                .background((isConnected ? Color.teal : Color.secondary).opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isConnected)
    }
}

private enum AssistantTheme {
    static let background = Color(.systemGroupedBackground)
}

#Preview {
    AssistantNativeContentView()
}
