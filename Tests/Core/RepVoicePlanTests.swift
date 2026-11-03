import Testing
@testable import SpottrCore

@Test func everyCountedRepIsCountedAndEveryThirdCleanRepAddsALine() {
    var plan = RepVoicePlan()
    plan.start(at: 0)
    #expect(plan.next(at: 0.2)?.clip == "start")
    plan.rep(1, clean: true, at: 2)
    #expect(plan.next(at: 2.1)?.clip == "count-01")
    plan.rep(2, clean: false, at: 4)
    plan.rep(3, clean: true, at: 6)
    // Count 2 was still waiting when rep 3 arrived: only the newer number is said, then the motivational line.
    #expect(plan.queue.map(\.clip) == ["count-03", "motivate-1"])
    #expect(plan.next(at: 6.1)?.clip == "count-03")
    #expect(plan.next(at: 6.9)?.clip == "motivate-1")
    plan.rep(6, clean: true, at: 12)
    #expect(plan.queue.map(\.clip) == ["count-06", "motivate-2"])   // the lines rotate
    plan.rep(9, clean: false, at: 18)
    #expect(plan.queue.map(\.clip) == ["count-09"])                 // a rep with a form issue gets no praise
}

@Test func staleLinesAreDroppedAndCountsStopAtThirty() {
    var plan = RepVoicePlan()
    plan.rep(3, clean: true, at: 0)
    #expect(plan.next(at: 2)?.clip == "motivate-1")   // the count waited 2 s, past its 1.5 s limit
    plan.rep(31, clean: false, at: 10)
    #expect(plan.queue.isEmpty)
    plan.rep(33, clean: true, at: 20)
    #expect(plan.queue.map(\.clip) == ["motivate-2"])
    plan.closing(at: 30)
    #expect(plan.next(at: 37)?.clip == "closing-1")
    plan.closing(at: 40)
    #expect(plan.queue.map(\.clip) == ["closing-2"])
    plan.clear()
    #expect(plan.next(at: 40) == nil)
    #expect(RepVoicePlan.allClips.count == 41 && RepVoicePlan.Coach.goggins.folder == "DemoVoice/goggins-reps")
}
