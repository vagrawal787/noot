import SwiftUI
import GRDB
import AVFoundation

struct MeetingView: View {
    let meeting: Meeting
    @State private var notes: [Note] = []
    @State private var contexts: [Context] = []
    @StateObject private var audioPlayer = MeetingAudioPlayer()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Meeting header
                header

                Divider()

                // Contexts
                if !contexts.isEmpty {
                    contextsSection
                }

                // Audio recording
                if meeting.audioPath != nil {
                    audioSection
                }

                // Associated notes
                notesSection
            }
            .padding()
        }
        .onAppear {
            loadData()
            loadAudio()
        }
        .onChange(of: meeting.id) { _ in
            // Reset state when meeting changes
            loadData()
            loadAudio()
        }
    }

    private var contextsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Contexts")
                .font(.headline)

            FlowLayout(spacing: 6) {
                ForEach(contexts) { context in
                    HStack(spacing: 4) {
                        Image(systemName: context.type == .domain ? "folder" : "arrow.triangle.branch")
                            .font(.caption2)
                        Text(context.name)
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentColor.opacity(0.1))
                    )
                }
            }
        }
    }

    private func loadAudio() {
        audioPlayer.stop()
        if let path = meeting.audioPath {
            audioPlayer.load(url: URL(fileURLWithPath: path))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = meeting.title {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
            } else {
                Text("Meeting")
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)

                Text(meeting.startedAt, style: .date)
                Text(meeting.startedAt, style: .time)

                if let endedAt = meeting.endedAt {
                    Text("–")
                    Text(endedAt, style: .time)

                    if let duration = meeting.duration {
                        Text("(\(formatDuration(duration)))")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("– Ongoing")
                        .foregroundColor(.green)
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Audio Recording")
                .font(.headline)

            HStack(spacing: 12) {
                // Play/Pause button
                Button(action: {
                    if audioPlayer.isPlaying {
                        audioPlayer.pause()
                    } else if let path = meeting.audioPath {
                        audioPlayer.play(url: URL(fileURLWithPath: path))
                    }
                }) {
                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 20)
                }
                .buttonStyle(.bordered)

                // Progress slider
                VStack(spacing: 2) {
                    Slider(
                        value: Binding(
                            get: { audioPlayer.currentTime },
                            set: { audioPlayer.seek(to: $0) }
                        ),
                        in: 0...max(audioPlayer.duration, 1)
                    )

                    HStack {
                        Text(formatTime(audioPlayer.currentTime))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                        Spacer()
                        Text(formatTime(audioPlayer.duration))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }

                // Open in Finder
                Button(action: {
                    if let path = meeting.audioPath {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                }) {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes (\(notes.count))")
                .font(.headline)

            if notes.isEmpty {
                Text("No notes captured during this meeting")
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else {
                ForEach(notes) { note in
                    MeetingNoteRow(note: note)
                }
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? ""
    }

    private func loadData() {
        let meetingId = meeting.id
        do {
            try Database.shared.read { db in
                // Load notes
                let noteMeetings = try NoteMeeting
                    .filter(NoteMeeting.Columns.meetingId == meetingId)
                    .fetchAll(db)
                let noteIds = noteMeetings.map { $0.noteId }
                notes = try Note
                    .filter(noteIds.contains(Note.Columns.id))
                    .order(Note.Columns.createdAt)
                    .fetchAll(db)

                // Load contexts
                let meetingContexts = try MeetingContext
                    .filter(MeetingContext.Columns.meetingId == meetingId)
                    .fetchAll(db)
                let contextIds = meetingContexts.map { $0.contextId }
                contexts = try Context
                    .filter(contextIds.contains(Context.Columns.id))
                    .fetchAll(db)
            }
        } catch {
            print("Failed to load meeting data: \(error)")
        }
    }
}

struct MeetingNoteRow: View {
    let note: Note

    private var preview: String {
        // Remove image/video markdown for clean preview
        note.content
            .replacingOccurrences(of: #"!\[[^\]]*\]\([^)]+\)"#, with: "📷", options: .regularExpression)
            .replacingOccurrences(of: #"🎬\s*\[[^\]]*\]\([^)]+\)"#, with: "🎬", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Button(action: navigateToNote) {
            HStack(alignment: .top) {
                Text(note.createdAt, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .leading)

                Text(preview)
                    .font(.body)
                    .lineLimit(3)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.05))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func navigateToNote() {
        NotificationCenter.default.post(
            name: .navigateToNote,
            object: nil,
            userInfo: ["noteId": note.id]
        )
    }
}

struct MeetingListView: View {
    @State private var meetings: [Meeting] = []
    @Binding var selectedMeeting: Meeting?

    var body: some View {
        List(selection: $selectedMeeting) {
            ForEach(meetings) { meeting in
                MeetingListRow(meeting: meeting)
                    .tag(meeting)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedMeeting = meeting
                    }
            }
        }
        .listStyle(.plain)
        .onAppear {
            loadMeetings()
        }
    }

    private func loadMeetings() {
        do {
            meetings = try Database.shared.read { db in
                try Meeting.recent(limit: 50).fetchAll(db)
            }
        } catch {
            print("Failed to load meetings: \(error)")
        }
    }
}

struct MeetingListRow: View {
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(meeting.title ?? "Meeting")
                    .fontWeight(.medium)
                Spacer()
                if meeting.isOngoing {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                }
            }

            HStack {
                Text(meeting.startedAt, style: .date)
                Text(meeting.startedAt, style: .time)
                if let duration = meeting.duration {
                    Text("(\(Int(duration / 60)) min)")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Audio Player

class MeetingAudioPlayer: ObservableObject {
    private var player: AVAudioPlayer?
    private var timer: Timer?

    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0

    func load(url: URL) {
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            duration = player?.duration ?? 0
        } catch {
            print("Failed to load audio: \(error)")
        }
    }

    func play(url: URL) {
        if player == nil {
            load(url: url)
        }

        player?.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    func stop() {
        player?.stop()
        isPlaying = false
        currentTime = 0
        stopTimer()
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.player else { return }
            DispatchQueue.main.async {
                self.currentTime = player.currentTime
                if !player.isPlaying {
                    self.isPlaying = false
                    self.stopTimer()
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

#Preview {
    MeetingView(meeting: Meeting(title: "Team Standup"))
        .frame(width: 500, height: 400)
}
