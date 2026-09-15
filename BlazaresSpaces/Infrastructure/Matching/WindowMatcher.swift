import CoreGraphics
import Foundation

struct PersistedWindowMatchRequest: Equatable, Sendable {
    let id: ManagedWindowID
    let descriptor: PersistedWindowDescriptor
    let logicalGeometry: LogicalWindowGeometry
}

struct RankedWindowCandidate: Equatable, Sendable {
    let window: WindowSnapshot
    let score: Int
    let evidence: [String]
}

enum WindowMatchResult: Equatable, Sendable {
    case highConfidence(RankedWindowCandidate)
    case probable(RankedWindowCandidate)
    case ambiguous([RankedWindowCandidate])
    case missing

    var selectedRuntimeIdentity: WindowRuntimeIdentity? {
        switch self {
        case let .highConfidence(candidate), let .probable(candidate): return candidate.window.runtimeIdentity
        case .ambiguous, .missing: return nil
        }
    }
}

/// Privacy-preserving and deterministic matcher. Titles and enumeration order
/// never contribute to confidence; ties remain explicit ambiguity.
struct WindowMatcher: Sendable {
    let highConfidenceThreshold: Int
    let probableThreshold: Int
    let requiredWinningMargin: Int
    let policy: WindowManagementPolicy

    init(
        highConfidenceThreshold: Int = 80,
        probableThreshold: Int = 55,
        requiredWinningMargin: Int = 15,
        policy: WindowManagementPolicy = .developmentDefaults
    ) {
        self.highConfidenceThreshold = highConfidenceThreshold
        self.probableThreshold = probableThreshold
        self.requiredWinningMargin = requiredWinningMargin
        self.policy = policy
    }

    func match(_ request: PersistedWindowMatchRequest, among windows: [WindowSnapshot]) -> WindowMatchResult {
        let ranked = windows.compactMap { score($0, against: request) }.sorted(by: rankedBefore)
        guard let best = ranked.first, best.score >= probableThreshold else { return .missing }

        let plausible = ranked.filter { best.score - $0.score < requiredWinningMargin }
        if plausible.count > 1 { return .ambiguous(plausible) }
        return best.score >= highConfidenceThreshold ? .highConfidence(best) : .probable(best)
    }

    /// Matches all records without ever binding one runtime window twice. A
    /// collision is downgraded to ambiguity for every affected durable record.
    func matchAll(
        _ requests: [PersistedWindowMatchRequest],
        among windows: [WindowSnapshot]
    ) -> [ManagedWindowID: WindowMatchResult] {
        var results = Dictionary(uniqueKeysWithValues: requests.map { ($0.id, match($0, among: windows)) })
        var owners: [WindowRuntimeIdentity: [ManagedWindowID]] = [:]
        for (id, result) in results {
            if let runtimeID = result.selectedRuntimeIdentity { owners[runtimeID, default: []].append(id) }
        }

        for (runtimeID, durableIDs) in owners where durableIDs.count > 1 {
            guard let candidateWindow = windows.first(where: { $0.runtimeIdentity == runtimeID }) else { continue }
            for durableID in durableIDs {
                let previous = results[durableID]
                let score: Int
                switch previous {
                case let .highConfidence(candidate), let .probable(candidate): score = candidate.score
                case .ambiguous, .missing, .none: score = probableThreshold
                }
                results[durableID] = .ambiguous([
                    RankedWindowCandidate(
                        window: candidateWindow,
                        score: score,
                        evidence: ["Runtime candidate also matches another durable window record."]
                    )
                ])
            }
        }
        return results
    }

    private func score(
        _ window: WindowSnapshot,
        against request: PersistedWindowMatchRequest
    ) -> RankedWindowCandidate? {
        let descriptor = request.descriptor
        guard policy.exclusionReason(for: window) == nil, window.role == descriptor.role else { return nil }

        var value = 20
        var evidence = ["Role matches."]
        if let expectedBundle = descriptor.bundleIdentifier {
            guard window.bundleIdentifier == expectedBundle else { return nil }
            value += 50
            evidence.append("Bundle identifier matches.")
        } else {
            guard window.applicationName.caseInsensitiveCompare(descriptor.applicationName) == .orderedSame else { return nil }
            value += 25
            evidence.append("Application name matches; no durable bundle identifier is available.")
        }

        if descriptor.subrole == window.subrole {
            value += descriptor.subrole == nil ? 5 : 10
            evidence.append("Window subrole matches.")
        }

        let expected = request.logicalGeometry.absolute.cgRect
        let sizeSimilarity = similarity(expected.width, window.frame.width) + similarity(expected.height, window.frame.height)
        let sizePoints = Int((sizeSimilarity * 7.5).rounded())
        value += sizePoints
        if sizePoints >= 10 { evidence.append("Window dimensions are similar.") }

        let scale = max(hypot(expected.width, expected.height), 1)
        let distance = hypot(expected.midX - window.frame.midX, expected.midY - window.frame.midY)
        let centerSimilarity = max(0, 1 - Double(distance / (scale * 2)))
        let positionPoints = Int((centerSimilarity * 5).rounded())
        value += positionPoints
        if positionPoints >= 4 { evidence.append("Window position is similar.") }

        return RankedWindowCandidate(window: window, score: value, evidence: evidence)
    }

    private func similarity(_ expected: CGFloat, _ actual: CGFloat) -> Double {
        let denominator = max(abs(expected), abs(actual), 1)
        return max(0, 1 - Double(abs(expected - actual) / denominator))
    }

    private func rankedBefore(_ lhs: RankedWindowCandidate, _ rhs: RankedWindowCandidate) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        let lhsKey = runtimeSortKey(lhs.window.runtimeIdentity)
        let rhsKey = runtimeSortKey(rhs.window.runtimeIdentity)
        return lhsKey < rhsKey
    }

    private func runtimeSortKey(_ identity: WindowRuntimeIdentity) -> String {
        "\(identity.processIdentifier):\(identity.accessibilityIdentifier ?? ""):\(identity.enumerationIndex)"
    }
}

