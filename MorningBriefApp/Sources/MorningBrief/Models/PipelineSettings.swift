import Foundation

struct PipelineSettings: Equatable {
    var lookbackHours: Int
    var minDurationSeconds: Int
    var transcriptDeferHours: Int
    var maxTranscriptChars: Int
    var claudeModel: String

    /// Range checks mirroring what the pipeline can sensibly handle.
    var validationError: String? {
        if !(1...336).contains(lookbackHours) {
            return "Lookback must be between 1 and 336 hours."
        }
        if !(0...3600).contains(minDurationSeconds) {
            return "Minimum duration must be between 0 and 3600 seconds."
        }
        if !(0...168).contains(transcriptDeferHours) {
            return "Transcript defer window must be between 0 and 168 hours."
        }
        if !(1000...500_000).contains(maxTranscriptChars) {
            return "Max transcript length must be between 1,000 and 500,000 characters."
        }
        if claudeModel.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Claude model must not be empty."
        }
        return nil
    }
}
