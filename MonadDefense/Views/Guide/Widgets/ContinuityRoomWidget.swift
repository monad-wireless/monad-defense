import Charts
import SwiftUI

/// M5, Eqs. (6.3)–(6.4) on a 1-D room of 15 m with a door at the right end.
/// Two crowds walk right and left on upwind finite volumes; walls reflect, so
/// the count changes only through the open door.
struct ContinuityRoomWidget: View {
    private static let cells = 30
    private static let dx = 0.5

    @State private var speed = 0.8
    @State private var inflow = 0.15
    @State private var doorOpen = true
    @State private var opposing = false
    @State private var running = true
    @State private var right = [Double](repeating: 0, count: cells)
    @State private var left = [Double](repeating: 0, count: cells)
    @State private var trace: [XY] = []
    @State private var time = 0.0
    @State private var flux = (inflow: 0.0, outflow: 0.0)

    private var count: Double { (right.reduce(0, +) + left.reduce(0, +)) * Self.dx }

    var body: some View {
        WidgetLayout(
            formula: "\\frac{dN_\\Omega}{dt}=\(tex(flux.inflow, 3))-\(tex(flux.outflow, 3))=\(tex(flux.inflow - flux.outflow, 3)),\\quad N_\\Omega=\(tex(count, 2))",
            words: "people move inside the room all the time, yet $N$ changes only at the door. Close it and $N$ freezes while the crowd still moves. A low-variance trace says nothing about the door; an unknown door flux is a missing variable."
        ) {
            VStack(spacing: 6) {
                Chart {
                    ForEach(0..<Self.cells, id: \.self) { i in
                        BarMark(x: .value("x", (Double(i) + 0.5) * Self.dx), y: .value("right", right[i]), width: .fixed(5))
                            .foregroundStyle(GuideColors.accent)
                        BarMark(x: .value("x", (Double(i) + 0.5) * Self.dx), y: .value("left", left[i]), width: .fixed(5))
                            .foregroundStyle(GuideColors.amber)
                    }
                    RuleMark(x: .value("door", 15)).foregroundStyle(doorOpen ? .green : .red)
                }
                .chartXScale(domain: 0...15)
                .chartYScale(domain: 0...1.6)
                .chartXAxisLabel("position (m) · blue right · orange left · door at 15 m")
                Chart(trace) { p in
                    LineMark(x: .value("t", p.x), y: .value("N", p.y)).foregroundStyle(GuideColors.accent)
                }
                .chartYScale(domain: 0...max(10, count * 1.3))
                .chartXAxisLabel("time (s) · people in the room")
            }
        } controls: {
            GSlider(label: "Walking speed", value: $speed, range: 0.1...1.5, unit: "m/s")
            GSlider(label: "Inflow at the door", value: $inflow, range: 0...0.5, unit: "pers/s")
            GChoice(label: "Door", selection: $doorOpen, options: [(true, "open"), (false, "closed")])
            GChoice(label: "Start", selection: $opposing, options: [(false, "one crowd"), (true, "two opposing crowds")])
            HStack {
                Button(running ? "Pause" : "Run") { running.toggle() }
                Spacer()
                Button("Reset") { reset() }
            }
            .font(.footnote)
        }
        .onAppear { reset() }
        .onChange(of: opposing) { reset() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                if running { for _ in 0..<4 { step(0.05) } }
            }
        }
    }

    private func reset() {
        var r = [Double](repeating: 0, count: Self.cells)
        var l = [Double](repeating: 0, count: Self.cells)
        for i in 4..<16 {
            r[i] = 0.6
            if opposing { l[i + 8] = 0.6 }
        }
        right = r
        left = l
        time = 0
        trace = []
    }

    /// One upwind step. Every face flux leaves one cell and enters its
    /// neighbour; walls reflect walkers into the other crowd. Only the open
    /// door changes the total.
    private func step(_ dt: Double) {
        let v = speed, n = Self.cells
        let r = right, l = left
        let turnLeftWall = v * l[0]
        let turnRightWall = doorOpen ? 0 : v * r[n - 1]
        var nr = r, nl = l
        for i in 0..<n {
            let inFace = i == 0 ? turnLeftWall : v * r[i - 1]
            nr[i] = max(0, r[i] + dt / Self.dx * (inFace - v * r[i]))
        }
        for i in 0..<n {
            let inFace = i == n - 1 ? (doorOpen ? inflow : turnRightWall) : v * l[i + 1]
            nl[i] = max(0, l[i] + dt / Self.dx * (inFace - v * l[i]))
        }
        right = nr
        left = nl
        flux = (doorOpen ? inflow : 0, doorOpen ? v * r[n - 1] : 0)
        time += dt
        trace = Array((trace + [XY(id: Int(time * 1000), x: time, y: count)]).suffix(300))
    }
}
