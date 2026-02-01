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

                Rectangle()
                    .fill(NootTheme.cyan.opacity(0.2))
                    .frame(height: 1)

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
        .background(NootTheme.background)
        .onAppear {
            loadData()
            loadAudio()
        }
        .onChange(of: meeting.id) { _ in
            loadData()
            loadAudio()
        }
    }

    private var contextsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONTEXTS")
                .font(NootTheme.monoFontSmall)
                .foregroundColor(NootTheme.textMuted)

            FlowLayout(spacing: 6) {
                ForEach(contexts) { context in
                    HStack(spacing: 4) {
                        Image(systemName: context.iconName)
                            .font(.caption2)
                        Text(context.name)
                            .font(NootTheme.monoFontSmall)
                    }
                    .foregroundColor(context.themeColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(context.themeColor.opacity(0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(context.themeColor.opacity(0.3), lineWidth: 0.5)
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
                Text(title.uppercased())
                    .font(NootTheme.monoFontLarge)
                    .foregroundColor(NootTheme.textPrimary)
            } else {
                Text("MEETING")
                    .font(NootTheme.monoFontLarge)
                    .foregroundColor(NootTheme.textPrimary)
            }

            HStack {
                Image(systemName: "clock")
                    .foregroundColor(NootTheme.cyan)

                Text(meeting.startedAt, style: .date)
                Text(meeting.startedAt, style: .time)

                if let endedAt = meeting.endedAt {
                    Text("–")
                    Text(endedAt, style: .time)

                    if let duration = meeting.duration {
                        Text("(\(formatDuration(duration)))")
                            .foregroundColor(NootTheme.textMuted)
                    }
                } else {
                    Text("– ONGOING")
                        .foregroundColor(NootTheme.success)
                        .neonGlow(NootTheme.success, radius: 4)
                }
            }
            .font(NootTheme.monoFontSmall)
            .foregroundColor(NootTheme.textSecondary)
        }
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AUDIO RECORDING")
                .font(NootTheme.monoFontSmall)
                .foregroundColor(NootTheme.textMuted)

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
                        .foregroundColor(audioPlayer.isPlaying ? NootTheme.magenta : NootTheme.cyan)
                        .frame(width: 20)
                }
                .buttonStyle(NeonButtonStyle(color: audioPlayer.isPlaying ? NootTheme.magenta : NootTheme.cyan))

                // Progress slider
                VStack(spacing: 2) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Track background
                            RoundedRectangle(cornerRadius: 2)
                                .fill(NootTheme.surface)
                                .frame(height: 4)

                            // Progress
                            RoundedRectangle(cornerRadius: 2)
                                .fill(NootTheme.cyan)
                                .frame(width: geometry.size.width * (audioPlayer.duration > 0 ? audioPlayer.currentTime / audioPlayer.duration : 0), height: 4)
                                .neonGlow(NootTheme.cyan, radius: 2)
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let progress = value.location.x / geometry.size.width
                                    let time = max(0, min(audioPlayer.duration, audioPlayer.duration * progress))
                                    audioPlayer.seek(to: time)
                                }
                        )
                    }
                    .frame(height: 4)

                    HStack {
                        Text(formatTime(audioPlayer.currentTime))
                            .font(NootTheme.monoFontSmall)
                            .foregroundColor(NootTheme.textMuted)
                        Spacer()
                        Text(formatTime(audioPlayer.duration))
                            .font(NootTheme.monoFontSmall)
                            .foregroundColor(NootTheme.textMuted)
                    }
                }

                // Open in Finder
                Button(action: {
                    if let path = meeting.audioPath {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                }) {
                    Image(systemName: "folder")
                        .foregroundColor(NootTheme.textMuted)
                }
                .buttonStyle(.plain)
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
            Text("NOTES (\(notes.count))")
                .font(NootTheme.monoFontSmall)
                .foregroundColor(NootTheme.textMuted)

            if notes.isEmpty {
                Text("No notes captured during this meeting")
                    .foregroundColor(NootTheme.textMuted)
                    .font(NootTheme.monoFontSmall)
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
        note.content
            .replacingOccurrences(of: #"!\[[^\]]*\]\([^)]+\)"#, with: "[img]", options: .regularExpression)
            .replacingOccurrences(of: #"🎬\s*\[[^\]]*\]\([^)]+\)"#, with: "[rec]", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Button(action: navigateToNote) {
            HStack(alignment: .top) {
                Text(note.createdAt, style: .time)
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.cyan)
                    .frame(width: 60, alignment: .leading)

                Text(preview)
                    .font(NootTheme.monoFont)
                    .lineLimit(3)
                    .foregroundColor(NootTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(NootTheme.textMuted)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(NootTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(NootTheme.cyan.opacity(0.2), lineWidth: 0.5)
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
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("MEETINGS")
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.magenta)
                Spacer()
                Text("\(meetings.count)")
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(NootTheme.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(NootTheme.surface)
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(NootTheme.backgroundLight)

            Rectangle()
                .fill(NootTheme.magenta.opacity(0.3))
                .frame(height: 1)

            // Meetings list
            if meetings.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.2")
                        .font(.system(size: 32))
                        .foregroundColor(NootTheme.textMuted)
                    Text("NO MEETINGS")
                        .font(NootTheme.monoFontSmall)
                        .foregroundColor(NootTheme.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(NootTheme.background)
            } else {
                List(selection: $selectedMeeting) {
                    ForEach(meetings) { meeting in
                        MeetingListRow(meeting: meeting)
                            .tag(meeting)
                            .listRowBackground(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedMeeting?.id == meeting.id ? NootTheme.magenta.opacity(0.15) : Color.clear)
                            )
                            .listRowSeparator(.hidden)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedMeeting = meeting
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(NootTheme.background)
            }
        }
        .background(NootTheme.background)
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
                    .font(NootTheme.monoFont)
                    .foregroundColor(NootTheme.textPrimary)
                Spacer()
                if meeting.isOngoing {
                    Circle()
                        .fill(NootTheme.recording)
                        .frame(width: 8, height: 8)
                        .neonGlow(NootTheme.recording, radius: 4)
                }
            }

            HStack {
                Text(meeting.startedAt, style: .date)
                Text(meeting.startedAt, style: .time)
                if let duration = meeting.duration {
                    Text("(\(Int(duration / 60)) min)")
                }
            }
            .font(NootTheme.monoFontSmall)
            .foregroundColor(NootTheme.textMuted)
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
        .preferredColorScheme(.dark)
}
