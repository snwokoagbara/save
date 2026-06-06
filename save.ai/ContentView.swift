import SwiftUI

struct ContentView: View {
    private let summary = DemoData.claimSummary
    private let receipts = DemoData.receipts
    private let claimPackets = DemoData.claimPackets
    private let taxExport = DemoData.taxExport

    var body: some View {
        TabView {
            HomeView(summary: summary, claimPackets: claimPackets)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            ClaimsView(claimPackets: claimPackets)
                .tabItem {
                    Label("Claims", systemImage: "doc.badge.arrow.up")
                }

            ReceiptsView(receipts: receipts)
                .tabItem {
                    Label("Receipts", systemImage: "receipt.fill")
                }

            KaiView(summary: summary, taxExport: taxExport)
                .tabItem {
                    Label("Kai", systemImage: "sparkles")
                }

            ProfileView(taxExport: taxExport)
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle.fill")
                }
        }
        .tint(.teal)
    }
}

private struct HomeView: View {
    let summary: ClaimSummary
    let claimPackets: [ClaimPacket]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    MoneyHeroCard(summary: summary)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Next best actions")
                            .font(.headline)

                        ActionRow(
                            icon: "envelope.badge.shield.half.filled",
                            title: "Connect Gmail",
                            detail: "Find receipts from pharmacies, dentists, vision care, and administrators."
                        )
                        ActionRow(
                            icon: "building.columns.fill",
                            title: "Link bank",
                            detail: "Catch medical purchases you forgot to upload."
                        )
                        ActionRow(
                            icon: "doc.viewfinder.fill",
                            title: "Prepare first claim",
                            detail: "\(claimPackets.first?.administratorName ?? "HealthEquity") packet is ready for review."
                        )
                    }
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("MVP signal")
                            .font(.headline)

                        HStack(spacing: 12) {
                            MetricTile(value: "5 min", label: "first estimate")
                            MetricTile(value: "30%+", label: "claim completion")
                            MetricTile(value: "$200+", label: "90-day recovery")
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("SAVE")
        }
    }
}

private struct MoneyHeroCard: View {
    let summary: ClaimSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Kai found")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(summary.totalClaimable.currency)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.7)
                        .accessibilityIdentifier("claimableEstimate")
                    Text("in HSA/FSA money you can claim back from reviewed receipts.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(.teal, in: Circle())
            }

            HStack(spacing: 10) {
                StatusPill(text: "\(summary.readyClaimCount) claims ready", systemImage: "doc.text.fill")
                StatusPill(text: "\(summary.needsReviewCount) needs review", systemImage: "exclamationmark.triangle.fill")
            }
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal)
    }
}

private struct ClaimsView: View {
    let claimPackets: [ClaimPacket]

    var body: some View {
        NavigationStack {
            List {
                Section("Ready packets") {
                    ForEach(claimPackets) { packet in
                        NavigationLink {
                            ClaimDetailView(packet: packet)
                        } label: {
                            ClaimPacketRow(packet: packet)
                        }
                    }
                }

                Section("Submission posture") {
                    Label("Guided packet first, in-app submission where administrators support it.", systemImage: "arrow.triangle.2.circlepath")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Claims")
        }
    }
}

private struct ClaimPacketRow: View {
    let packet: ClaimPacket

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(packet.administratorName)
                    .font(.headline)
                Spacer()
                Text(packet.total.currency)
                    .font(.headline)
                    .foregroundStyle(.teal)
            }

            Text(packet.submissionMode.rawValue)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                StatusPill(text: packet.status.rawValue, systemImage: "checkmark.circle.fill")
                Text("\(packet.lineItems.count) eligible items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct ClaimDetailView: View {
    let packet: ClaimPacket

    var body: some View {
        List {
            Section("Packet") {
                LabeledContent("Administrator", value: packet.administratorName)
                LabeledContent("Amount", value: packet.total.currency)
                LabeledContent("Mode", value: packet.submissionMode.rawValue)
                LabeledContent("Status", value: packet.status.rawValue)
            }

            Section("Included items") {
                ForEach(packet.lineItems) { item in
                    LineItemRow(item: item)
                }
            }

            Section("Kai guidance") {
                Text(packet.submissionMode == .guidedPacket ? "Download the packet, submit it in your administrator portal, then come back so Kai can track status." : "This administrator supports in-app submission in the MVP roadmap. Kai keeps a guided fallback available.")
                    .font(.callout)
            }
        }
        .navigationTitle("Claim packet")
    }
}

private struct ReceiptsView: View {
    let receipts: [Receipt]

    var body: some View {
        NavigationStack {
            List {
                Section("Imported receipts") {
                    ForEach(receipts) { receipt in
                        NavigationLink {
                            ReceiptDetailView(receipt: receipt)
                        } label: {
                            ReceiptRow(receipt: receipt)
                        }
                    }
                }
            }
            .navigationTitle("Receipts")
            .toolbar {
                Button {
                } label: {
                    Image(systemName: "camera.fill")
                }
                .accessibilityLabel("Scan receipt")
            }
        }
    }
}

private struct ReceiptRow: View {
    let receipt: Receipt

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(receipt.merchant)
                    .font(.headline)
                Spacer()
                Text(receipt.reimbursableTotal.currency)
                    .font(.headline)
                    .foregroundStyle(receipt.reimbursableTotal > 0 ? .teal : .secondary)
            }

            Text("\(receipt.source.rawValue) - \(receipt.lineItems.count) items")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct ReceiptDetailView: View {
    let receipt: Receipt

    var body: some View {
        List {
            Section("Receipt") {
                LabeledContent("Merchant", value: receipt.merchant)
                LabeledContent("Source", value: receipt.source.rawValue)
                LabeledContent("Total", value: receipt.total.currency)
                LabeledContent("Claimable", value: receipt.reimbursableTotal.currency)
            }

            Section("Line items") {
                ForEach(receipt.lineItems) { item in
                    LineItemRow(item: item)
                }
            }
        }
        .navigationTitle(receipt.merchant)
    }
}

private struct LineItemRow: View {
    let item: ReceiptLineItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.eligibility.symbolName)
                .foregroundStyle(item.eligibility == .needsReview ? .orange : .teal)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.body)
                Text("\(item.eligibility.rawValue) - \(Int(item.confidence * 100))% confidence")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(item.amount.currency)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 4)
    }
}

private struct KaiView: View {
    let summary: ClaimSummary
    let taxExport: TaxExport

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MessageBubble(
                        speaker: "Kai",
                        text: "I found \(summary.totalClaimable.currency) you can claim back now. One receipt has a vitamin item I want you to review before I include it."
                    )
                    MessageBubble(
                        speaker: "Kai",
                        text: "Your 2026 Schedule A medical report is also ready with \(taxExport.totalMedicalExpenses.currency) in itemized backup."
                    )
                    MessageBubble(
                        speaker: "You",
                        text: "Prepare my HealthEquity claim packet."
                    )
                    MessageBubble(
                        speaker: "Kai",
                        text: "Done. I filled the amount, grouped eligible items, attached receipts, and kept a guided submission checklist."
                    )

                    HStack {
                        Button {
                        } label: {
                            Label("Scan", systemImage: "camera.fill")
                        }
                        .buttonStyle(.bordered)

                        Button {
                        } label: {
                            Label("Claim", systemImage: "doc.badge.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Kai")
        }
    }
}

private struct MessageBubble: View {
    let speaker: String
    let text: String

    private var isKai: Bool {
        speaker == "Kai"
    }

    var body: some View {
        VStack(alignment: isKai ? .leading : .trailing, spacing: 6) {
            Text(speaker)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(text)
                .font(.body)
                .padding(14)
                .background(isKai ? Color(.secondarySystemGroupedBackground) : Color.teal.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: isKai ? .leading : .trailing)
    }
}

private struct ProfileView: View {
    let taxExport: TaxExport

    var body: some View {
        NavigationStack {
            List {
                Section("Connected sources") {
                    ConnectionRow(title: "Gmail", state: "Ready to scan", symbol: "envelope.fill")
                    ConnectionRow(title: "Plaid", state: "Bank match enabled", symbol: "building.columns.fill")
                    ConnectionRow(title: "kai@ forwarding", state: "Personal inbox active", symbol: "tray.and.arrow.down.fill")
                }

                Section("Year-end tax assist") {
                    LabeledContent("Tax year", value: "\(taxExport.year)")
                    LabeledContent("Medical expenses", value: taxExport.totalMedicalExpenses.currency)
                    Button {
                    } label: {
                        Label("Export PDF and CSV", systemImage: "square.and.arrow.down")
                    }
                }

                Section("Privacy posture") {
                    Text("PHI minimization, encrypted receipt storage, and no unnecessary medical detail in model prompts.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Profile")
        }
    }
}

private struct ConnectionRow: View {
    let title: String
    let state: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.teal)
                .frame(width: 28)
            VStack(alignment: .leading) {
                Text(title)
                Text(state)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ActionRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.teal)
                .frame(width: 32, height: 32)
                .background(.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct MetricTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct StatusPill: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.teal.opacity(0.12), in: Capsule())
            .foregroundStyle(.teal)
    }
}

#Preview {
    ContentView()
}
