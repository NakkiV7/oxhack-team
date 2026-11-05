import Foundation

public enum MembershipPlan: String, CaseIterable, Sendable {
    case monthly, lifetime

    public var productID: String { "com.omarchoudhry.spottr.\(rawValue)" }
    public var kind: MembershipProductKind { self == .monthly ? .autoRenewable : .nonConsumable }
}

public enum MembershipProductKind: Sendable {
    case autoRenewable, nonConsumable, unsupported
}

public struct MembershipTransaction: Sendable {
    public let id: UInt64
    public let productID: String
    public let kind: MembershipProductKind
    public let expirationDate: Date?
    public let gracePeriodExpirationDate: Date?
    public let revocationDate: Date?
    public let isUpgraded: Bool

    public init(id: UInt64 = 0, productID: String, kind: MembershipProductKind, expirationDate: Date? = nil,
                gracePeriodExpirationDate: Date? = nil, revocationDate: Date? = nil, isUpgraded: Bool = false) {
        self.id = id
        self.productID = productID
        self.kind = kind
        self.expirationDate = expirationDate
        self.gracePeriodExpirationDate = gracePeriodExpirationDate
        self.revocationDate = revocationDate
        self.isUpgraded = isUpgraded
    }
}

public enum MembershipVerification: Sendable {
    case verified(MembershipTransaction)
    case unverified(MembershipTransaction)
}

public struct MembershipAccess: Equatable, Sendable {
    public let activePlans: Set<MembershipPlan>
    public let expiresAt: Date?
    public var hasAccess: Bool { !activePlans.isEmpty }
    public var lifetime: Bool { activePlans.contains(.lifetime) }
    public var hasOverlappingSubscription: Bool { lifetime && activePlans.contains(.monthly) }

    public func mayPurchase(_ plan: MembershipPlan) -> Bool {
        !lifetime && !activePlans.contains(plan)
    }

    public static func resolve(_ transactions: [MembershipVerification], now: Date) -> MembershipAccess {
        let valid = transactions.compactMap { verification -> (MembershipPlan, Date?)? in
            guard case .verified(let transaction) = verification,
                  transaction.revocationDate == nil, !transaction.isUpgraded,
                  let plan = MembershipPlan.allCases.first(where: { $0.productID == transaction.productID }),
                  plan.kind == transaction.kind else { return nil }
            if plan == .lifetime { return (plan, nil) }
            guard let expiration = transaction.expirationDate else { return nil }
            let deadline = max(expiration, transaction.gracePeriodExpirationDate ?? expiration)
            return deadline > now ? (plan, deadline) : nil
        }
        return MembershipAccess(activePlans: Set(valid.map(\.0)), expiresAt: valid.compactMap(\.1).max())
    }
}
