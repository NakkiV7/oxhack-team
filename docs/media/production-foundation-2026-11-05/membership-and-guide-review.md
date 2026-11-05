# Actual beta screenshots — build 19

These are unedited captures from the installed Spottr 0.1 (19) beta on the existing shared iPhone simulator (iPhone 17 Pro, iOS 26.5). They are review evidence, **not App Store-approved screenshots or product approval**. No new simulator or screen configuration was created.

- `membership-beta.png`: the Profile → Membership journey, abstract gem, unrestricted beta access, optional purchases, Apple confirmation wording, and the actual unavailable-products state. No prices were fabricated for the screenshot.
- `paused-squat-guide-beta.png`: the Profile → Film your exercises → Paused squats guide, showing a faceless stick figure, the two-second hold label, framing guidance, and the measured timing requirement.

Both journeys passed in `MembershipFlowTests`. The final native test result passed 213 checks: all 210 `SpottrTests` excluding only `MembershipStoreKitTests`, both membership/guide journeys, and `OfflineMVPFlowTests`. Four local StoreKit tests remain separately blocked by the observed iOS 26.5 configuration setup failure; the screenshot does not imply successful purchases or an active tester code.

`membership-guide-review-receipt.json` records the result bundle, source attachment names, simulator identity and image SHA-256 hashes. Existing simulator apps and data were preserved; UI journeys used fresh isolated data namespaces.
