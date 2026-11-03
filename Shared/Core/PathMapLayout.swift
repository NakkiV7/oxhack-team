import Foundation

/// Deterministic positions for drawing a training path. Positions come only from the path itself: the main chain in level
/// order, side steps in their own lanes beside the step they belong to. Progress never moves a node.
public struct PathMapLayout: Equatable, Sendable {
    public enum Orientation: Sendable { case vertical, horizontal }
    public enum Role: String, Sendable {
        /// The last step of the main chain.
        case goal
        /// A step the camera can assess.
        case milestone
        case standard
        /// The optional side branch.
        case optional
    }
    public struct Position: Equatable, Sendable {
        public let x: Double
        public let y: Double
        /// Order along the path (half steps for side steps placed before their dependant).
        public let axis: Double
        /// 0 for the main chain; positive for the optional branch, negative for supporting prerequisites.
        public let lane: Int
    }
    public struct Edge: Equatable, Sendable {
        public enum Kind: Sendable { case prerequisite, support }
        public let from: String
        public let to: String
        public let kind: Kind
    }

    public let positions: [String: Position]
    public let width: Double
    public let height: Double
    /// Reading order for VoiceOver and the list view: along the path, then across lanes.
    public let order: [String]
    public let edges: [Edge]

    public static func role(of node: PathNode, in path: TrainingPath) -> Role {
        if node.id == path.goalNode { return .goal }
        if node.optional { return .optional }
        return PathCapability.of(node.id) == .practiceLog ? .standard : .milestone
    }

    /// - Parameters: step is the distance between consecutive steps; lane the distance between lanes; wave the sideways
    ///   swing of the main chain that keeps it from reading as a ruler.
    public static func make(path: TrainingPath, orientation: Orientation = .vertical, step: Double = 150, lane laneSpacing: Double = 118,
                            padding: Double = 64, wave: Double = 14) -> PathMapLayout {
        let family = path.goal.family
        let chain = path.nodes.filter { !$0.optional && $0.entry?.family == family }
            .sorted { ($0.entry?.level ?? 0) < ($1.entry?.level ?? 0) }.map(\.id)
        var slots: [String: (axis: Double, lane: Int)] = [:]
        for (index, id) in chain.enumerated() { slots[id] = (Double(index), 0) }
        var used = Set(chain.indices.map { "\(Double($0)):0" })
        for node in path.nodes where slots[node.id] == nil {
            let anchor = node.supports ?? path.nodes.first { $0.prerequisites.contains(node.id) }?.id
            let anchorAxis = anchor.flatMap { slots[$0]?.axis } ?? 0
            let axis = node.optional ? anchorAxis : max(0, anchorAxis - 0.5)
            var lane = node.optional ? 1 : -1
            while used.contains("\(axis):\(lane)") { lane += lane > 0 ? 1 : -1 }
            used.insert("\(axis):\(lane)")
            slots[node.id] = (axis, lane)
        }
        let lanes = slots.values.map(\.lane), minLane = min(0, lanes.min() ?? 0), maxLane = max(0, lanes.max() ?? 0)
        let maxAxis = slots.values.map(\.axis).max() ?? 0
        var positions: [String: Position] = [:]
        for (id, slot) in slots {
            let swing = slot.lane == 0 ? (Int(slot.axis.rounded()) % 2 == 1 ? wave : -wave) : 0
            switch orientation {
            case .vertical:
                positions[id] = .init(x: padding + wave + Double(slot.lane - minLane) * laneSpacing + swing, y: padding + slot.axis * step,
                                      axis: slot.axis, lane: slot.lane)
            case .horizontal:
                positions[id] = .init(x: padding + slot.axis * step, y: padding + wave + Double(maxLane - slot.lane) * laneSpacing + swing,
                                      axis: slot.axis, lane: slot.lane)
            }
        }
        let across = 2 * (padding + wave) + Double(maxLane - minLane) * laneSpacing, along = 2 * padding + maxAxis * step
        let order = positions.keys.sorted { a, b in
            let p = positions[a]!, q = positions[b]!
            return p.axis != q.axis ? p.axis < q.axis : p.lane > q.lane
        }
        let edges = path.nodes.flatMap { node in node.prerequisites.map { Edge(from: $0, to: node.id, kind: .prerequisite) } }
            + path.nodes.compactMap { node in node.optional ? node.supports.map { Edge(from: node.id, to: $0, kind: .support) } : nil }
        return .init(positions: positions, width: orientation == .vertical ? across : along, height: orientation == .vertical ? along : across,
                     order: order, edges: edges)
    }
}
