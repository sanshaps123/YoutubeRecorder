import Foundation

/// Exports an array of CaptionSegments to a standard .srt subtitle file.
struct SRTExporter {

    /// Export caption segments to a .srt file at the given URL.
    /// - Parameters:
    ///   - segments: The transcription segments to export.
    ///   - url: The destination file URL (should have .srt extension).
    static func export(segments: [CaptionSegment], to url: URL) throws {
        guard !segments.isEmpty else {
            print("[SRT] No segments to export.")
            return
        }

        var srtContent = ""

        for (index, segment) in segments.enumerated() {
            let number = index + 1
            let startTimestamp = formatSRTTime(segment.startTime)
            let endTimestamp = formatSRTTime(segment.endTime)

            srtContent += "\(number)\n"
            srtContent += "\(startTimestamp) --> \(endTimestamp)\n"
            srtContent += "\(segment.text)\n"
            srtContent += "\n"
        }

        try srtContent.write(to: url, atomically: true, encoding: .utf8)
        print("[SRT] Exported \(segments.count) segments to: \(url.lastPathComponent)")
    }

    /// Format a TimeInterval as SRT timestamp: HH:MM:SS,mmm
    /// Example: 65.5 → "00:01:05,500"
    private static func formatSRTTime(_ time: TimeInterval) -> String {
        let totalSeconds = max(0, time)
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        let seconds = Int(totalSeconds) % 60
        let milliseconds = Int((totalSeconds.truncatingRemainder(dividingBy: 1)) * 1000)

        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }
}
