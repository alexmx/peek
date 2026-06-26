@testable import peek
import Testing

@Suite("InteractionManager Tests")
struct InteractionManagerTests {
    // MARK: - distributeDelta

    /// The ease-in-out weight curve used by the smooth-scroll path (∝ t·(1−t)).
    private func easeWeights(_ steps: Int) -> [Double] {
        (1...steps).map { i in
            let t = (Double(i) - 0.5) / Double(steps)
            return t * (1 - t)
        }
    }

    @Test
    func sumsToTotal() {
        let totals: [Int32] = [1200, -600, 1, -1, 7, 999, -1000]
        let stepCounts = [2, 3, 5, 10, 30, 40, 100]
        for total in totals {
            for steps in stepCounts {
                let parts = InteractionManager.distributeDelta(total, across: easeWeights(steps))
                #expect(parts.count == steps)
                #expect(parts.reduce(0, +) == total)
            }
        }
    }

    @Test
    func zeroTotal() {
        let parts = InteractionManager.distributeDelta(0, across: easeWeights(10))
        #expect(parts.count == 10)
        #expect(parts.allSatisfy { $0 == 0 })
    }

    @Test
    func zeroWeights() {
        let parts = InteractionManager.distributeDelta(500, across: [0, 0, 0])
        #expect(parts == [0, 0, 0])
    }

    @Test
    func easeShape() throws {
        let parts = InteractionManager.distributeDelta(1000, across: easeWeights(10))
        // The first/last step move less than a middle step — that asymmetry is what
        // renders as accel/decel rather than a constant-velocity scroll.
        #expect(try #require(parts.first) < parts[parts.count / 2])
        #expect(try #require(parts.last) < parts[parts.count / 2])
        #expect(parts.reduce(0, +) == 1000)
    }

    @Test
    func singleStep() {
        let parts = InteractionManager.distributeDelta(742, across: [0.25])
        #expect(parts == [742])
    }
}
