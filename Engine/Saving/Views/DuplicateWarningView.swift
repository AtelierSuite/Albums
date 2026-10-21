import SwiftUI

struct DuplicateWarningView: View {

    var session: SaveSession
    var matches: [DuplicateMatch]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(matches) { match in
                        HStack(spacing: 12.0) {
                            thumbnail(match.incomingThumbnail)
                            Image(systemName: "equal")
                                .foregroundStyle(.secondary)
                            thumbnail(match.existingThumbnail)
                            Text("Duplicates.FoundIn.\(match.location)", tableName: "Saving", bundle: .engine)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                } footer: {
                    Text("Duplicates.Message", tableName: "Saving", bundle: .engine)
                }
            }
            .navigationTitle(String(localized: "Duplicates.Title", table: "Saving", bundle: .engine))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        session.cancel()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8.0) {
                    if matches.count < session.items.count {
                        Button {
                            Task { await session.resolveDuplicates(skippingDuplicates: true) }
                        } label: {
                            Text("Duplicates.SkipDuplicates", tableName: "Saving", bundle: .engine)
                                .bold()
                        }
                        .buttonStyle(.glassProminent)
                    }
                    if matches.count < session.items.count {
                        saveAnywayButton
                            .buttonStyle(.glass)
                    } else {
                        saveAnywayButton
                            .buttonStyle(.glassProminent)
                    }
                }
                .controlSize(.extraLarge)
                .buttonSizing(.flexible)
                .buttonBorderShape(.capsule)
                .padding(20.0)
            }
        }
    }

    private var saveAnywayButton: some View {
        Button {
            Task { await session.resolveDuplicates(skippingDuplicates: false) }
        } label: {
            Text("Duplicates.SaveAnyway", tableName: "Saving", bundle: .engine)
                .bold()
        }
    }

    private func thumbnail(_ data: Data?) -> some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.secondary.opacity(0.2)
            }
        }
        .frame(width: 56.0, height: 56.0)
        .clipShape(.rect(cornerRadius: 8.0))
    }
}
