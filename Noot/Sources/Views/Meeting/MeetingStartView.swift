import SwiftUI

struct MeetingStartView: View {
    let onStart: (AudioSource) -> Void
    let onCancel: () -> Void

    @State private var selectedSource: AudioSource = .both

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Start Meeting")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 12) {
                Text("Audio Recording")
                    .font(.headline)

                ForEach(AudioSource.allCases, id: \.self) { source in
                    AudioSourceRow(
                        source: source,
                        isSelected: selectedSource == source
                    ) {
                        selectedSource = source
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.controlBackgroundColor))
            )

            Text(audioSourceDescription)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(height: 40)

            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape, modifiers: [])

                Button("Start Meeting") {
                    onStart(selectedSource)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(24)
        .frame(width: 320)
    }

    private var audioSourceDescription: String {
        switch selectedSource {
        case .microphone:
            return "Records your voice only. Use when you want to capture your own notes."
        case .system:
            return "Records computer audio only. Captures what you hear from other participants."
        case .both:
            return "Records both your voice and computer audio. Best for full meeting capture."
        }
    }
}

struct AudioSourceRow: View {
    let source: AudioSource
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                Image(systemName: iconForSource)
                    .frame(width: 20)

                Text(source.rawValue)

                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var iconForSource: String {
        switch source {
        case .microphone:
            return "mic"
        case .system:
            return "speaker.wave.2"
        case .both:
            return "mic.and.signal.meter"
        }
    }
}

#Preview {
    MeetingStartView(
        onStart: { _ in },
        onCancel: {}
    )
}
