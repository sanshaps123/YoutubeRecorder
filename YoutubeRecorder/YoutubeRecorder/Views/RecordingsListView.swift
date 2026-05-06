import SwiftUI
import AVFoundation
import QuickLookUI

/// Lists recent recordings from the save directory with thumbnails, metadata, and actions.
struct RecordingsListView: View {
    @State private var recordings: [RecordingFile] = []
    @State private var selectedURL: URL?
    private let settings = SettingsStore.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Recent Recordings", systemImage: "film.stack")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    loadRecordings()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(red: 0.08, green: 0.09, blue: 0.11))

            Divider().background(Color.white.opacity(0.1))

            if recordings.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "film.stack")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No recordings yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Your recordings will appear here after you record.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(recordings) { recording in
                            recordingRow(recording)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 400)
        .background(Color(red: 0.06, green: 0.07, blue: 0.09))
        .onAppear { loadRecordings() }
    }

    // MARK: - Row

    private func recordingRow(_ recording: RecordingFile) -> some View {
        HStack(spacing: 14) {
            // Thumbnail
            if let thumb = recording.thumbnail {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(0.05))
                    .frame(width: 80, height: 48)
                    .overlay(
                        Image(systemName: "play.rectangle.fill")
                            .foregroundStyle(.secondary)
                    )
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(recording.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    if let duration = recording.durationText {
                        Label(duration, systemImage: "clock")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Text(recording.sizeText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(recording.dateText)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 8) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([recording.url])
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")

                Button {
                    NSWorkspace.shared.open(recording.url)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help("Open in QuickTime")

                Button {
                    deleteRecording(recording)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.red.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help("Delete")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.02))
        .contentShape(Rectangle())
    }

    // MARK: - Data

    private func loadRecordings() {
        let dirPath = settings.saveDirectory
        let dirURL = URL(fileURLWithPath: dirPath)

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            recordings = []
            return
        }

        let movFiles = files.filter { $0.pathExtension.lowercased() == "mov" }
            .sorted { ($0.lastModified ?? .distantPast) > ($1.lastModified ?? .distantPast) }

        recordings = movFiles.prefix(50).map { RecordingFile(url: $0) }
    }

    private func deleteRecording(_ recording: RecordingFile) {
        try? FileManager.default.removeItem(at: recording.url)
        loadRecordings()
    }
}

// MARK: - Recording File Model

struct RecordingFile: Identifiable {
    let id: String
    let url: URL
    let name: String
    let sizeText: String
    let dateText: String
    let durationText: String?
    let thumbnail: NSImage?

    init(url: URL) {
        self.url = url
        self.id = url.lastPathComponent
        self.name = url.deletingPathExtension().lastPathComponent

        // File size
        let vals = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
        if let bytes = vals?.fileSize {
            let mb = Double(bytes) / 1_000_000
            if mb > 1000 {
                self.sizeText = String(format: "%.1f GB", mb / 1000)
            } else {
                self.sizeText = String(format: "%.1f MB", mb)
            }
        } else {
            self.sizeText = "—"
        }

        // Date
        if let date = vals?.creationDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            self.dateText = formatter.string(from: date)
        } else {
            self.dateText = "—"
        }

        // Duration
        let asset = AVURLAsset(url: url)
        let durationCM = asset.duration
        if durationCM.seconds > 0 && !durationCM.seconds.isNaN {
            let secs = Int(durationCM.seconds)
            let hrs = secs / 3600
            let mins = (secs % 3600) / 60
            let s = secs % 60
            if hrs > 0 {
                self.durationText = String(format: "%d:%02d:%02d", hrs, mins, s)
            } else {
                self.durationText = String(format: "%d:%02d", mins, s)
            }
        } else {
            self.durationText = nil
        }

        // Thumbnail
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 96)
        if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
            self.thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: 160, height: 96))
        } else {
            self.thumbnail = nil
        }
    }
}

// MARK: - URL Extension

private extension URL {
    var lastModified: Date? {
        try? resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
