import Engine
import SwiftUI
import UIKit

struct SuggestionGroup: Identifiable {
    let albumID: String
    let albumName: String
    let items: [EntitySuggestion]

    var id: String { albumID }
}

struct IntelligentSortResultsView: View {

    @Environment(\.dismiss) var dismiss

    var sortManager: IntelligentSortManager

    @State private var isConfirmingMove: Bool = false

    private var needsReview: [EntitySuggestion] {
        sortManager.suggestions.filter { ($0.topMatch?.confidence ?? .none) == .none }
    }

    private var suggestionGroups: [SuggestionGroup] {
        var order: [String] = []
        var grouped: [String: [EntitySuggestion]] = [:]
        var names: [String: String] = [:]
        for suggestion in sortManager.suggestions {
            guard let top = suggestion.topMatch, top.confidence != .none else { continue }
            if grouped[top.albumID] == nil {
                order.append(top.albumID)
                names[top.albumID] = top.albumName
            }
            grouped[top.albumID, default: []].append(suggestion)
        }
        let groups = order.map { albumID in
            SuggestionGroup(
                albumID: albumID,
                albumName: names[albumID] ?? "",
                items: (grouped[albumID] ?? []).sorted {
                    ($0.topMatch?.distance ?? 1) < ($1.topMatch?.distance ?? 1)
                }
            )
        }
        return groups.sorted {
            ($0.items.first?.topMatch?.distance ?? 1) < ($1.items.first?.topMatch?.distance ?? 1)
        }
    }

    private var hasStrongMatches: Bool {
        sortManager.suggestions.contains { $0.topMatch?.confidence == .strong }
    }

    private var hasSelections: Bool {
        sortManager.suggestions.contains { $0.selectedAlbumID != nil }
    }

    var body: some View {
        Group {
            if sortManager.targetAlbumCount == 0 {
                ContentUnavailableView {
                    Label(String(localized: "Sort.NoTargets", table: "Photos"),
                          systemImage: "rectangle.stack.badge.xmark")
                } description: {
                    Text("Sort.NoTargets.Message", tableName: "Photos")
                }
            } else if sortManager.suggestions.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "Sort.NoPics", table: "Photos"),
                          systemImage: "photo.on.rectangle")
                } description: {
                    Text("Sort.NoPics.Message", tableName: "Photos")
                }
            } else {
                resultsList
            }
        }
    }

    private var resultsList: some View {
        List {
            ForEach(suggestionGroups) { group in
                Section {
                    carousel(for: group.items)
                    Button(String(localized: "Sort.AcceptAllInGroup", table: "Photos")) {
                        withAnimation(.smooth.speed(2.0)) {
                            for item in group.items {
                                item.selectedAlbumID = item.topMatch?.albumID
                            }
                        }
                    }
                    .tint(.accent)
                    Button(String(localized: "Sort.DeselectAllInGroup", table: "Photos")) {
                        withAnimation(.smooth.speed(2.0)) {
                            for item in group.items {
                                item.selectedAlbumID = nil
                            }
                        }
                    }
                    .tint(.secondary)
                } header: {
                    HStack {
                        Text(verbatim: group.albumName)
                        Spacer()
                        Text("Duplicates.GroupCount.\(group.items.count)", tableName: "Photos")
                    }
                    .textCase(nil)
                }
            }
            if !needsReview.isEmpty {
                Section {
                    carousel(for: needsReview)
                } header: {
                    Text("Sort.NeedsReview", tableName: "Photos")
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .confirm) {
                    isConfirmingMove = true
                }
                .accessibilityLabel(
                    Text("Sort.MovePics.\(sortManager.pendingMoveCount)", tableName: "Photos")
                )
                .disabled(sortManager.pendingMoveCount == 0)
            }
            if hasStrongMatches {
                ToolbarItem(placement: .bottomBar) {
                    Button(String(localized: "Sort.AcceptAllStrong", table: "Photos")) {
                        withAnimation(.smooth.speed(2.0)) {
                            sortManager.acceptAllStrongMatches()
                        }
                    }
                }
            }
            ToolbarSpacer(.fixed, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button(String(localized: "Sort.DeselectAll", table: "Photos"), role: .destructive) {
                    withAnimation(.smooth.speed(2.0)) {
                        sortManager.deselectAll()
                    }
                }
                .disabled(!hasSelections)
            }
        }
        .alert(
            String(
                localized: """
                Sort.MoveConfirmation.\
                \(sortManager.pendingMoveCount)-\(sortManager.pendingDestinationCount)
                """,
                table: "Photos"
            ),
            isPresented: $isConfirmingMove
        ) {
            Button("Shared.Yes") {
                Task {
                    await sortManager.commit()
                    let moves = sortManager.committedMoves
                    let collectionID = sortManager.collectionID
                    let message = await IntelligentSortManager.moveSummaryMessage(
                        for: moves, collectionID: collectionID
                    )
                    ToastManager.shared.show(ToastItem(
                        message: message,
                        undo: moves.isEmpty ? nil : {
                            await IntelligentSortManager.revert(moves, collectionID: collectionID)
                        }
                    ))
                    dismiss()
                }
            }
            Button("Shared.No", role: .cancel) {}
        }
    }

    private func carousel(for items: [EntitySuggestion]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12.0) {
                ForEach(items) { suggestion in
                    SuggestionCard(suggestion: suggestion, dataActor: sortManager.dataActor)
                }
            }
            .padding(.vertical, 4.0)
            .padding(.horizontal, 18.0)
        }
        .listRowInsets(EdgeInsets(top: 14.0, leading: 0, bottom: 14.0, trailing: 0))
    }
}

// MARK: - Suggestion Card

struct SuggestionCard: View {

    @Bindable var suggestion: EntitySuggestion
    var dataActor: DataActor

    private var chosenMatch: AlbumMatch? {
        guard let selected = suggestion.selectedAlbumID else { return nil }
        return suggestion.matches.first { $0.albumID == selected }
    }

    private var isIncluded: Bool { suggestion.selectedAlbumID != nil }

    var body: some View {
        Button {
            withAnimation(.smooth.speed(2.0)) { toggleInclusion() }
        } label: {
            VStack(spacing: 6.0) {
                PicLabel(pic: suggestion.pic)
                    .frame(width: 120.0, height: 120.0)
                    .clipShape(.rect(cornerRadius: 10.0))
                    .overlay {
                        if !suggestion.matches.isEmpty {
                            SelectionOverlay(isIncluded)
                        }
                    }
                    .overlay(alignment: .topLeading) { medoidBadge }

                VStack(spacing: 2.0) {
                    Text(suggestion.pic.name)
                        .font(.caption)
                        .lineLimit(1)
                    confidenceLabel
                }
            }
            .frame(width: 120.0)
        }
        .buttonStyle(.plain)
        .disabled(suggestion.matches.isEmpty)
        .contextMenu { destinationMenuContent }
    }

    private func toggleInclusion() {
        if isIncluded {
            suggestion.selectedAlbumID = nil
        } else {
            suggestion.selectedAlbumID = suggestion.topMatch?.albumID
        }
    }

    @ViewBuilder
    private var medoidBadge: some View {
        if let medoidID = chosenMatch?.medoidPicID ?? suggestion.topMatch?.medoidPicID {
            MedoidThumbnail(picID: medoidID, dataActor: dataActor)
                .frame(width: 30.0, height: 30.0)
                .clipShape(.rect(cornerRadius: 6.0))
                .overlay(
                    RoundedRectangle(cornerRadius: 6.0)
                        .strokeBorder(.white, lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.3), radius: 2.0, x: 0, y: 1.0)
                .padding(6.0)
        }
    }

    @ViewBuilder
    private var confidenceLabel: some View {
        if suggestion.isUnanalyzable {
            Label(String(localized: "Sort.Unanalyzable", table: "Photos"),
                  systemImage: "questionmark.square.dashed")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            let confidence = suggestion.topMatch?.confidence ?? .none
            Label(confidenceText(confidence), systemImage: confidenceIcon(confidence))
                .font(.caption2)
                .foregroundStyle(confidenceColor(confidence))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var destinationMenuContent: some View {
        ForEach(suggestion.matches) { match in
            Button {
                suggestion.selectedAlbumID = match.albumID
            } label: {
                if suggestion.selectedAlbumID == match.albumID {
                    Label(match.albumName, systemImage: "checkmark")
                } else {
                    Text(verbatim: match.albumName)
                }
            }
        }
        if !suggestion.matches.isEmpty {
            Divider()
            Button(role: .destructive) {
                suggestion.selectedAlbumID = nil
            } label: {
                Label(String(localized: "Sort.Skip", table: "Photos"), systemImage: "xmark")
            }
        }
    }

    private func confidenceText(_ confidence: SortConfidence) -> String {
        switch confidence {
        case .strong: String(localized: "Sort.Confidence.Strong", table: "Photos")
        case .likely: String(localized: "Sort.Confidence.Likely", table: "Photos")
        case .weak: String(localized: "Sort.Confidence.Weak", table: "Photos")
        case .none: String(localized: "Sort.NoSuggestion", table: "Photos")
        }
    }

    private func confidenceIcon(_ confidence: SortConfidence) -> String {
        switch confidence {
        case .strong: "checkmark.seal.fill"
        case .likely: "checkmark.circle"
        case .weak: "questionmark.circle"
        case .none: "minus.circle"
        }
    }

    private func confidenceColor(_ confidence: SortConfidence) -> Color {
        switch confidence {
        case .strong: .green
        case .likely: .accent
        case .weak: .orange
        case .none: .secondary
        }
    }
}

// MARK: - Medoid Thumbnail

struct MedoidThumbnail: View {

    let picID: String
    var dataActor: DataActor

    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.05))
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .task(id: picID) {
                if let data = await dataActor.thumbnailData(forPicWithID: picID) {
                    image = UIImage(data: data)
                }
            }
    }
}
