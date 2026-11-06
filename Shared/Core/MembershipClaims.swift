import Foundation

/// Ownership context only. A claim never proves that an Apple entitlement is active.
public struct MembershipClaim: Codable, Hashable, Sendable {
    public let originalTransactionID: UInt64
    public let plan: MembershipPlan

    public init(originalTransactionID: UInt64, plan: MembershipPlan) {
        self.originalTransactionID = originalTransactionID
        self.plan = plan
    }

    init?(transaction: MembershipTransaction) {
        guard transaction.originalID != 0,
              let plan = MembershipPlan.allCases.first(where: { $0.productID == transaction.productID }),
              plan.kind == transaction.kind else { return nil }
        self.init(originalTransactionID: transaction.originalID, plan: plan)
    }
}

/// Synchronous protected I/O cannot suspend between the coordinator's owner check and write.
@MainActor public protocol MembershipClaimStore {
    func load(accountID: UUID) throws -> Set<MembershipClaim>
    func save(_ claims: Set<MembershipClaim>, accountID: UUID) throws
}

@MainActor public final class ProtectedMembershipClaimStore: MembershipClaimStore {
    private struct Saved: Codable {
        let version: Int
        let accountID: UUID
        let claims: Set<MembershipClaim>
    }
    private let root: URL
    public init(root: URL) { self.root = root }

    private func file(accountID: UUID) -> URL {
        root.appendingPathComponent("Accounts").appendingPathComponent(accountID.uuidString)
            .appendingPathComponent("membership-claims.json")
    }
    public func load(accountID: UUID) throws -> Set<MembershipClaim> {
        let url = file(accountID: accountID)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        try ProtectedLocalStorage.protect(url.deletingLastPathComponent())
        try ProtectedLocalStorage.protect(url)
        let saved = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: url))
        guard saved.version == 1, saved.accountID == accountID,
              saved.claims.allSatisfy({ $0.originalTransactionID != 0 }) else { throw CocoaError(.fileReadCorruptFile) }
        return saved.claims
    }
    public func save(_ claims: Set<MembershipClaim>, accountID: UUID) throws {
        guard claims.allSatisfy({ $0.originalTransactionID != 0 }) else { throw CocoaError(.fileWriteInvalidFileName) }
        let data = try JSONEncoder().encode(Saved(version: 1, accountID: accountID, claims: claims))
        try ProtectedLocalStorage.write(data, to: file(accountID: accountID))
    }
}
