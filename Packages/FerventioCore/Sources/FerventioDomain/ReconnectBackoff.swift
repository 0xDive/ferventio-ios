public enum ReconnectBackoff {
    public static let maximumAttempts = 6
    public static let maximumDelayMilliseconds = 30_000

    public static func delayMilliseconds(forAttempt attempt: Int) -> Int {
        let attempt = max(attempt, 0)
        let shift = min(attempt, 20)
        let exponential = 1_000 << shift
        return min(exponential, maximumDelayMilliseconds)
    }
}
