import Foundation

/// Tracks cumulative Anthropic API usage (tokens and estimated cost).
/// Persists data across launches using UserDefaults.
@Observable
final class APIUsageTracker {
    static let shared = APIUsageTracker()

    // MARK: - Stored totals

    private(set) var totalInputTokens: Int {
        didSet { save() }
    }
    private(set) var totalOutputTokens: Int {
        didSet { save() }
    }
    private(set) var totalCacheCreationTokens: Int {
        didSet { save() }
    }
    private(set) var totalCacheReadTokens: Int {
        didSet { save() }
    }
    private(set) var totalRequests: Int {
        didSet { save() }
    }

    // MARK: - Pricing (per million tokens)

    /// Sonnet 4.5 pricing as of 2025
    static let inputPricePerMTok: Double = 3.0
    static let outputPricePerMTok: Double = 15.0
    static let cacheWritePricePerMTok: Double = 3.75
    static let cacheReadPricePerMTok: Double = 0.30

    // MARK: - Computed

    var estimatedCost: Double {
        let inputCost  = Double(totalInputTokens) / 1_000_000 * Self.inputPricePerMTok
        let outputCost = Double(totalOutputTokens) / 1_000_000 * Self.outputPricePerMTok
        let cacheWriteCost = Double(totalCacheCreationTokens) / 1_000_000 * Self.cacheWritePricePerMTok
        let cacheReadCost  = Double(totalCacheReadTokens) / 1_000_000 * Self.cacheReadPricePerMTok
        return inputCost + outputCost + cacheWriteCost + cacheReadCost
    }

    var totalTokens: Int {
        totalInputTokens + totalOutputTokens
    }

    // MARK: - Init

    private init() {
        let defaults = UserDefaults.standard
        self.totalInputTokens = defaults.integer(forKey: Keys.inputTokens)
        self.totalOutputTokens = defaults.integer(forKey: Keys.outputTokens)
        self.totalCacheCreationTokens = defaults.integer(forKey: Keys.cacheCreationTokens)
        self.totalCacheReadTokens = defaults.integer(forKey: Keys.cacheReadTokens)
        self.totalRequests = defaults.integer(forKey: Keys.requests)
    }

    // MARK: - Recording

    /// Record token usage from a single API response.
    func record(inputTokens: Int, outputTokens: Int,
                cacheCreationTokens: Int = 0, cacheReadTokens: Int = 0) {
        totalInputTokens += inputTokens
        totalOutputTokens += outputTokens
        totalCacheCreationTokens += cacheCreationTokens
        totalCacheReadTokens += cacheReadTokens
        totalRequests += 1
    }

    /// Reset all tracked usage.
    func reset() {
        totalInputTokens = 0
        totalOutputTokens = 0
        totalCacheCreationTokens = 0
        totalCacheReadTokens = 0
        totalRequests = 0
    }

    // MARK: - Persistence

    private enum Keys {
        static let inputTokens = "api_usage_input_tokens"
        static let outputTokens = "api_usage_output_tokens"
        static let cacheCreationTokens = "api_usage_cache_creation_tokens"
        static let cacheReadTokens = "api_usage_cache_read_tokens"
        static let requests = "api_usage_requests"
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(totalInputTokens, forKey: Keys.inputTokens)
        defaults.set(totalOutputTokens, forKey: Keys.outputTokens)
        defaults.set(totalCacheCreationTokens, forKey: Keys.cacheCreationTokens)
        defaults.set(totalCacheReadTokens, forKey: Keys.cacheReadTokens)
        defaults.set(totalRequests, forKey: Keys.requests)
    }
}
