import SwiftUI

struct MeetingStatusView: View {
    @ObservedObject private var meetingManager = MeetingManager.shared
    @State private var elapsedTime: TimeInterval = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 8) {
            // Recording indicator
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .opacity(pulseOpacity)

            VStack(alignment: .leading, spacing: 2) {
                Text("Meeting")
                    .font(.caption)
                    .fontWeight(.medium)
                Text(formatDuration(elapsedTime))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            Button(action: endMeeting) {
                Image(systemName: "stop.fill")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Circle().fill(Color.red))
            }
            .buttonStyle(.plain)
            .help("End Meeting")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 2)
        )
        .onReceive(timer) { _ in
            if let meeting = meetingManager.currentMeeting {
                elapsedTime = Date().timeIntervalSince(meeting.startedAt)
            }
        }
    }

    @State private var pulseOpacity: Double = 1.0

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    private func endMeeting() {
        NotificationCenter.default.post(name: .toggleMeeting, object: nil)
    }
}

#Preview {
    MeetingStatusView()
        .frame(width: 180)
        .padding()
}
