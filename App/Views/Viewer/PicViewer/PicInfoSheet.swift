import Engine
import SwiftUI

struct PicInfoSheet: View {

    @Environment(\.dismiss) var dismiss

    var pic: Pic
    var pixelSize: CGSize?
    var albumName: String?

    @State var result: ContentCredentialsScanResult?

    var body: some View {
        NavigationStack {
            List {
                ContentCredentialsSection(result: result)
                Section {
                    LabeledContent {
                        Text(pic.dateAdded, format: .dateTime)
                    } label: {
                        Text("Info.DateAdded", tableName: "ContentCredentials")
                    }
                    if let pixelSize, pixelSize.width > 0.0, pixelSize.height > 0.0 {
                        PicDimensionsRow(pixelSize: pixelSize)
                    }
                    if let albumName {
                        LabeledContent {
                            Text(albumName)
                        } label: {
                            Text("Info.Album", tableName: "ContentCredentials")
                        }
                    }
                } header: {
                    Text("Info.Details", tableName: "ContentCredentials")
                }
            }
            .navigationTitle(Text("Info", tableName: "ContentCredentials"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) {
                        dismiss()
                    }
                }
            }
        }
        .task(id: pic.id) {
            let dataActor = DataActor.shared
            var scanResult = await dataActor.contentCredentials(forPicWithID: pic.id)
            if scanResult == .notScanned {
                result = nil
                await ContentCredentialsScanner.shared.scan(picID: pic.id, in: dataActor)
                scanResult = await dataActor.contentCredentials(forPicWithID: pic.id)
            }
            withAnimation(.smooth.speed(2.0)) {
                result = scanResult
            }
        }
    }
}

struct ContentCredentialsSection: View {

    var result: ContentCredentialsScanResult?

    var body: some View {
        switch result {
        case nil:
            Section {
                HStack(spacing: 8.0) {
                    ProgressView()
                    Text("Checking", tableName: "ContentCredentials")
                        .foregroundStyle(.secondary)
                }
            } header: {
                header
            }
        case .notScanned:
            Section {
                Text("NotChecked", tableName: "ContentCredentials")
                    .foregroundStyle(.secondary)
            } header: {
                header
            } footer: {
                Text("NotChecked.Description", tableName: "ContentCredentials")
            }
        case .notFound:
            Section {
                Text("NoProvenance", tableName: "ContentCredentials")
                    .foregroundStyle(.secondary)
            } header: {
                header
            } footer: {
                Text("NoProvenance.Description", tableName: "ContentCredentials")
            }
        case .found(let credentials):
            found(credentials)
        }
    }

    var header: some View {
        Text("ContentCredentials", tableName: "ContentCredentials")
    }

    @ViewBuilder
    func found(_ credentials: ContentCredentials) -> some View {
        Section {
            ContentCredentialsSummaryRow(credentials: credentials)
            if let generator = credentials.generator {
                LabeledContent {
                    Text([generator, credentials.generatorVersion].compactMap { $0 }.joined(separator: " "))
                } label: {
                    Text("Generator", tableName: "ContentCredentials")
                }
            }
            if let signer = credentials.signer {
                LabeledContent {
                    Text(signer)
                } label: {
                    Text("Signer", tableName: "ContentCredentials")
                }
            }
            if let signedAt = credentials.signedAt {
                LabeledContent {
                    Text(signedAt, format: .dateTime)
                } label: {
                    Text("SignedAt", tableName: "ContentCredentials")
                }
            }
            LabeledContent {
                ContentCredentialsValidationLabel(validation: credentials.validation)
            } label: {
                Text("Signature", tableName: "ContentCredentials")
            }
            if credentials.doNotTrain {
                LabeledContent {
                    Text("Training.NotAllowed", tableName: "ContentCredentials")
                } label: {
                    Text("Training", tableName: "ContentCredentials")
                }
            }
        } header: {
            header
        } footer: {
            Text("Found.Description", tableName: "ContentCredentials")
        }
        if !credentials.ingredients.isEmpty {
            Section {
                ForEach(Array(credentials.ingredients.enumerated()), id: \.offset) { _, ingredient in
                    ContentCredentialsIngredientRow(ingredient: ingredient)
                }
            } header: {
                Text("Ingredients", tableName: "ContentCredentials")
            }
        }
    }
}

extension ContentCredentials.SourceType? {
    var label: LocalizedStringResource {
        switch self {
        case .aiGenerated: AIContentKind.generated.label
        case .aiAssisted: AIContentKind.assisted.label
        case .digitalCapture: LocalizedStringResource("Source.DigitalCapture", table: "ContentCredentials")
        case .digitalCreation: LocalizedStringResource("Source.DigitalCreation", table: "ContentCredentials")
        case nil: LocalizedStringResource("Source.Unknown", table: "ContentCredentials")
        }
    }

    var systemImage: String {
        switch self {
        case .aiGenerated: AIContentKind.generated.systemImage
        case .aiAssisted: AIContentKind.assisted.systemImage
        case .digitalCapture: "camera"
        case .digitalCreation: "paintbrush.pointed"
        case nil: "checkmark.seal"
        }
    }
}

struct ContentCredentialsSummaryRow: View {

    var credentials: ContentCredentials

    var body: some View {
        HStack(spacing: 12.0) {
            Image(systemName: credentials.sourceType.systemImage)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 36.0, height: 36.0)
                .background(credentials.aiContentKind == nil ? Color.gray : Color.indigo, in: .circle)
            VStack(alignment: .leading, spacing: 2.0) {
                Text(credentials.sourceType.label)
                    .font(.headline)
                if let generator = credentials.generator {
                    Text(generator)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2.0)
    }
}

struct ContentCredentialsValidationLabel: View {

    var validation: ContentCredentials.Validation

    var key: LocalizedStringKey {
        switch validation {
        case .trusted: "Validation.Trusted"
        case .untrustedSigner: "Validation.UntrustedSigner"
        case .modified: "Validation.Modified"
        case .invalid: "Validation.Invalid"
        }
    }

    var systemImage: String {
        switch validation {
        case .trusted: "checkmark.seal.fill"
        case .untrustedSigner: "questionmark.diamond.fill"
        case .modified: "exclamationmark.triangle.fill"
        case .invalid: "xmark.seal.fill"
        }
    }

    var color: Color {
        switch validation {
        case .trusted: .green
        case .untrustedSigner: .orange
        case .modified, .invalid: .red
        }
    }

    var body: some View {
        HStack(spacing: 6.0) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
            Text(key, tableName: "ContentCredentials")
        }
        .fixedSize()
    }
}

struct ContentCredentialsIngredientRow: View {

    var ingredient: ContentCredentials.Ingredient

    var relationshipLabel: LocalizedStringResource? {
        switch ingredient.relationship {
        case "parentOf": LocalizedStringResource("Ingredient.Parent", table: "ContentCredentials")
        case "componentOf": LocalizedStringResource("Ingredient.Component", table: "ContentCredentials")
        case "inputTo": LocalizedStringResource("Ingredient.Input", table: "ContentCredentials")
        default: nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2.0) {
            if let title = ingredient.title {
                Text(title)
            } else {
                Text("Ingredient.Untitled", tableName: "ContentCredentials")
            }
            HStack(spacing: 4.0) {
                if let relationshipLabel {
                    Text(relationshipLabel)
                }
                if ingredient.hasCredentials {
                    if relationshipLabel != nil {
                        Text(verbatim: "·")
                    }
                    Image(systemName: ingredient.sourceType.systemImage)
                    Text(ingredient.sourceType.label)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
