import SwiftUI

struct ImportPreviewSheet: View {
    let preview: ImportPreview
    let importURL: URL
    let onImport: (ImportMode) -> Void
    let onCancel: () -> Void

    @State private var selectedMode: ImportMode = .merge

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.title2)
                    .foregroundColor(NootTheme.cyan)
                Text("Import Preview")
                    .font(NootTheme.monoFontTitle)
                    .foregroundColor(NootTheme.textPrimary)
                Spacer()
            }

            // Validation status
            if preview.isValid {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(NootTheme.success)
                    Text("Valid export detected")
                        .font(NootTheme.monoFont)
                        .foregroundColor(NootTheme.success)
                }
            } else {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(NootTheme.error)
                    Text("Invalid export format")
                        .font(NootTheme.monoFont)
                        .foregroundColor(NootTheme.error)
                }
            }

            Divider()
                .background(NootTheme.textMuted)

            // Content summary
            VStack(alignment: .leading, spacing: 12) {
                Text("Export Contents")
                    .font(NootTheme.monoFontLarge)
                    .foregroundColor(NootTheme.textPrimary)

                HStack(spacing: 24) {
                    StatBox(label: "Notes", value: "\(preview.noteCount)", color: NootTheme.cyan)
                    StatBox(label: "Contexts", value: "\(preview.contextCount)", color: NootTheme.magenta)
                    StatBox(label: "Meetings", value: "\(preview.meetingCount)", color: NootTheme.pink)
                    StatBox(label: "Attachments", value: "\(preview.attachmentCount)", color: NootTheme.purple)
                }

                if let manifest = preview.manifest {
                    HStack {
                        Text("Schema version: \(manifest.schemaVersion)")
                            .font(NootTheme.monoFontSmall)
                            .foregroundColor(NootTheme.textMuted)
                        Spacer()
                        Text("Exported: \(manifest.exportedAt.formatted())")
                            .font(NootTheme.monoFontSmall)
                            .foregroundColor(NootTheme.textMuted)
                    }
                }
            }
            .padding()
            .background(NootTheme.surface)
            .cornerRadius(8)

            // Warnings
            if !preview.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(NootTheme.warning)
                        Text("Warnings")
                            .font(NootTheme.monoFontLarge)
                            .foregroundColor(NootTheme.warning)
                    }

                    ForEach(preview.warnings, id: \.self) { warning in
                        HStack(alignment: .top) {
                            Text("•")
                            Text(warning)
                        }
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textSecondary)
                    }
                }
                .padding()
                .background(NootTheme.surface)
                .cornerRadius(8)
            }

            // Import mode selection
            if preview.isValid {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Import Mode")
                        .font(NootTheme.monoFontLarge)
                        .foregroundColor(NootTheme.textPrimary)

                    VStack(spacing: 8) {
                        ImportModeOption(
                            mode: .merge,
                            title: "Merge",
                            description: "Add imported items alongside existing data. Skips items that already exist.",
                            isSelected: selectedMode == .merge
                        ) {
                            selectedMode = .merge
                        }

                        ImportModeOption(
                            mode: .replace,
                            title: "Replace",
                            description: "Replace all existing data with imported data. A backup will be created first.",
                            isSelected: selectedMode == .replace
                        ) {
                            selectedMode = .replace
                        }
                    }
                }
            }

            Spacer()

            // Action buttons
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(NeonButtonStyle(color: NootTheme.textSecondary))

                Spacer()

                Button(action: { onImport(selectedMode) }) {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text(selectedMode == .replace ? "Replace All Data" : "Import")
                    }
                }
                .buttonStyle(NeonButtonStyle(color: selectedMode == .replace ? NootTheme.warning : NootTheme.cyan))
                .disabled(!preview.isValid)
            }
        }
        .padding(24)
        .frame(width: 500, height: 550)
        .background(NootTheme.background)
    }
}

// MARK: - Supporting Views

struct StatBox: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(NootTheme.monoFontLarge)
                .foregroundColor(color)
            Text(label)
                .font(NootTheme.monoFontSmall)
                .foregroundColor(NootTheme.textMuted)
        }
        .frame(minWidth: 60)
    }
}

struct ImportModeOption: View {
    let mode: ImportMode
    let title: String
    let description: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? NootTheme.cyan : NootTheme.textMuted)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(NootTheme.monoFont)
                        .foregroundColor(isSelected ? NootTheme.textPrimary : NootTheme.textSecondary)
                    Text(description)
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(12)
            .background(isSelected ? NootTheme.surface : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? NootTheme.cyan.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ImportPreviewSheet(
        preview: ImportPreview(
            isValid: true,
            schemaVersion: 1,
            noteCount: 150,
            contextCount: 12,
            meetingCount: 25,
            attachmentCount: 45,
            warnings: ["This export was created with a newer version of Noot."],
            manifest: ExportManifest(
                noteCount: 150,
                attachmentCount: 45,
                contextCount: 12,
                meetingCount: 25
            )
        ),
        importURL: URL(fileURLWithPath: "/tmp/test"),
        onImport: { _ in },
        onCancel: {}
    )
    .preferredColorScheme(.dark)
}
