import Foundation

// MARK: - Thread V3 geometry ("il filo diventa materia")
//
// PURE maths (Foundation only, no CoreGraphics / SwiftUI): it compiles on
// Linux and is checked by /home/claude/redesign/thread_proto/geometry_check.swift.
// The SwiftUI layer (`FiloSeta` in ArtKit.swift) only converts FiloVec2 → CGPoint.
// Reference prototype (same maths in JS): /home/claude/redesign/thread_proto/proto.html.
//
// Model (THREAD_V3_SPEC §2): ONE thread that passes through every taken tile
// and curves around its number with a loop ("asola"):
// - every tile = two cubics, A (entry E → apex M) and B (apex M → exit X);
// - between two tiles a straight link X(i) → E(i+1) parallel to the travel;
// - apex M on the circle of radius 22 around the tile centre:
//   straight → lateral side (vertical travel: right of travel; horizontal: below),
//   corner → quadrant between entry and exit, radial = normalize(−u + v);
// - start tile: born at the apex (side of the number), half loop to the exit;
//   end tile: entry → apex, the thread ends on the flank of the loop;
//   a lone tile: a short arc under the number ending at the bottom apex;
// - joins ("racing line", prototype tuning): each link is shifted sideways by
//   the average of what its two tiles prefer (straight/start/end → their loop
//   side, corner → inside of the turn; opposite wishes cancel). Both tiles use
//   the same offset, so continuity holds by construction.
// All metrics are for a 72-pt tile and scale with k = tileSide / 72.
// Sampling: flatten (24 steps per cubic) → resample every 2 pt by arc length →
// central-difference tangents/normals. Twist phase runs over the WHOLE length.

/// 2D vector (Double). Screen coordinates: x right, y DOWN.
struct FiloVec2: Equatable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    static let zero = FiloVec2(0, 0)

    static func + (a: FiloVec2, b: FiloVec2) -> FiloVec2 { FiloVec2(a.x + b.x, a.y + b.y) }
    static func - (a: FiloVec2, b: FiloVec2) -> FiloVec2 { FiloVec2(a.x - b.x, a.y - b.y) }
    static func * (a: FiloVec2, s: Double) -> FiloVec2 { FiloVec2(a.x * s, a.y * s) }
    static prefix func - (a: FiloVec2) -> FiloVec2 { FiloVec2(-a.x, -a.y) }

    func dot(_ b: FiloVec2) -> Double { x * b.x + y * b.y }
    /// z of the 3D cross product (positive = b is clockwise from self on screen).
    func cross(_ b: FiloVec2) -> Double { x * b.y - y * b.x }
    var length: Double { (x * x + y * y).squareRoot() }
    var normalized: FiloVec2 {
        let l = length
        return l < 1e-9 ? .zero : FiloVec2(x / l, y / l)
    }
    var angle: Double { atan2(y, x) }
    /// Rotated +90° on screen (y down): the "right-hand side" of a heading.
    var normalRight: FiloVec2 { FiloVec2(-y, x) }

    static func unit(_ angle: Double) -> FiloVec2 { FiloVec2(cos(angle), sin(angle)) }
    static func lerp(_ a: FiloVec2, _ b: FiloVec2, _ t: Double) -> FiloVec2 {
        FiloVec2(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
    }
    func distance(_ b: FiloVec2) -> Double { (self - b).length }
}

/// Values of THREAD_V3_SPEC for a 72-pt tile (scale with k = side / 72).
enum FiloThreadMetrics {
    static let referenceSide: Double = 72
    // loop
    static let loopRadius: Double = 22
    static let entryDistance: Double = 27
    /// Bézier handles as a fraction of the chord they span (entry → apex and
    /// apex → exit). Prototype tuning: the spec's fixed 8–9 pt handles gave
    /// 3–5 pt elbows; chord-relative handles give the 12–16 pt fillets the
    /// spec asks for (straight ≈ 15 pt handles, corner ≈ 6 pt).
    static let straightHandleRatio: Double = 0.43
    static let cornerHandleRatio: Double = 0.38
    /// Join offsets (prototype "racing line"): 8 pt toward a straight loop's
    /// side; 10.8 pt toward the inside of a corner (= the offset for which
    /// the corner is a true circular arc of radius 16.2 through the 22-pt apex).
    static let joinStraight: Double = 8
    static let joinCorner: Double = 10.8
    /// Arc (degrees) behind the bottom apex for a lone tile.
    static let singleTailDegrees: Double = 50
    // material
    static let width: Double = 5.2
    static let plyWidth: Double = 1.6
    static let plyAmplitude: Double = 0.95
    static let pitch: Double = 12
    static let fibreEvery: Double = 6
    static let fibreWidth: Double = 0.6
    static let fibreHalfLength: Double = 1.7
    static let fibreSlant: Double = 0.55
    static let fibreOpacity: Double = 0.22
    /// Over/under redraw of the shadow ply (twist up close) and satin sheen
    /// (reads as a satin line from afar) — prototype tuning.
    static let overUnderOpacity: Double = 0.5
    static let sheenOpacity: Double = 0.25
    static let sheenWidth: Double = 1.6
    static let shadowBlur: Double = 2
    static let shadowOffsetY: Double = 1.5
    static let shadowOpacity: Double = 0.25
    // terminals & outcomes
    static let startDot: Double = 7
    static let endDot: Double = 10
    static let frayLength: Double = 8
    static let frayAngleDegrees: Double = 12
    static let frayFibre: Double = 5
    static let recoil: Double = 6
    static let knotRadius: Double = 6
    static let knotSweepDegrees: Double = 270
    /// Arc-length sampling step, in points (not scaled).
    static let step: Double = 2
    /// Digit glyph half-size for a 72-pt tile (SF Rounded Medium 28: cap ≈ 20).
    static let glyphHalfWidth: Double = 8.5
    static let glyphHalfHeight: Double = 10
}

/// Shape of one tile's loop (what the morph interpolates).
struct FiloLoopParams: Equatable {
    var centre: FiloVec2
    var radius: Double
    /// Apex angle (M = centre + radius·unit(apexAngle)).
    var apexAngle: Double
    /// Tangent angle at the apex.
    var tangentAngle: Double
    /// Handle length as a fraction of each cubic's chord.
    var handleRatio: Double
    /// Arc (radians, signed) behind the apex; only for a lone tile.
    var tail: Double
    var entry: FiloVec2?
    var u: FiloVec2?
    var exit: FiloVec2?
    var v: FiloVec2?

    /// δ = tangent − apex angle, wrapped (always ±90° for real configurations).
    var relativeTangent: Double { FiloThreadBuilder.wrap(tangentAngle - apexAngle) }
    var apex: FiloVec2 { centre + FiloVec2.unit(apexAngle) * radius }
}

/// The 7 control points of a tile: A = a0 a1 a2 m, B = m b1 b2 b3.
struct FiloLoopControls: Equatable {
    var a0, a1, a2, m, b1, b2, b3: FiloVec2
}

struct FiloThreadSample: Equatable {
    var p: FiloVec2
    /// Arc length from the start of the thread.
    var s: Double
    var tangent: FiloVec2
    var normal: FiloVec2
}

/// Arc-length marks per tile: start of cubic A (entry), apex, end of cubic B (exit).
struct FiloThreadMarks: Equatable {
    var entry: [Double] = []
    var apex: [Double] = []
    var exit: [Double] = []
}

struct FiloThreadGeometry {
    var controls: [FiloLoopControls]
    var samples: [FiloThreadSample]
    var length: Double
    var marks: FiloThreadMarks
    static let empty = FiloThreadGeometry(controls: [], samples: [], length: 0, marks: FiloThreadMarks())
}

enum FiloTileKind: Equatable { case single, start, end, straight, corner }

enum FiloThreadBuilder {
    typealias M = FiloThreadMetrics

    // MARK: rules

    /// Side of a straight loop: horizontal travel → always below (+y);
    /// vertical travel → right of the travel direction.
    static func lateral(_ d: FiloVec2) -> FiloVec2 {
        abs(d.x) > 0.5 ? FiloVec2(0, 1) : d.normalRight
    }

    static func kind(u: FiloVec2?, v: FiloVec2?) -> FiloTileKind {
        switch (u, v) {
        case (nil, nil): return .single
        case (nil, _): return .start
        case (_, nil): return .end
        case let (u?, v?): return u.dot(v) > 0.99 ? .straight : .corner
        }
    }

    static func wrap(_ a: Double) -> Double {
        var a = a
        while a > .pi { a -= 2 * .pi }
        while a < -.pi { a += 2 * .pi }
        return a
    }

    static func directions(_ centres: [FiloVec2]) -> [(u: FiloVec2?, v: FiloVec2?)] {
        let n = centres.count
        var out: [(u: FiloVec2?, v: FiloVec2?)] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            var u: FiloVec2? = nil, v: FiloVec2? = nil
            if i > 0 { u = (centres[i] - centres[i - 1]).normalized }
            if i < n - 1 { v = (centres[i + 1] - centres[i]).normalized }
            out.append((u: u, v: v))
        }
        return out
    }

    /// Offset (×1, unscaled) a tile would like for its incoming / outgoing join.
    static func joinPreference(u: FiloVec2?, v: FiloVec2?, incoming: Bool) -> FiloVec2 {
        switch kind(u: u, v: v) {
        case .straight, .start, .end:
            return lateral((u ?? v)!) * M.joinStraight
        case .corner:
            return incoming ? v! * M.joinCorner : u! * (-M.joinCorner)
        case .single:
            return .zero
        }
    }

    /// Lateral offset of every join (count − 1), already scaled by k.
    static func joinOffsets(_ centres: [FiloVec2], k: Double) -> [FiloVec2] {
        guard centres.count >= 2 else { return [] }
        let d = directions(centres)
        return (0..<(centres.count - 1)).map { j in
            let a = joinPreference(u: d[j].u, v: d[j].v, incoming: false)
            let b = joinPreference(u: d[j + 1].u, v: d[j + 1].v, incoming: true)
            return (a + b) * (0.5 * k)
        }
    }

    // MARK: loops

    static func loopParams(centre c: FiloVec2, u: FiloVec2?, v: FiloVec2?,
                           offsetIn: FiloVec2, offsetOut: FiloVec2, k: Double) -> FiloLoopParams {
        let r = M.loopRadius * k
        let kd = kind(u: u, v: v)
        if kd == .single {
            return FiloLoopParams(centre: c, radius: r, apexAngle: .pi / 2, tangentAngle: 0,
                                  handleRatio: M.straightHandleRatio,
                                  tail: M.singleTailDegrees * .pi / 180,
                                  entry: nil, u: nil, exit: nil, v: nil)
        }
        var th: Double, ta: Double, ha: Double
        if kd == .corner, let u, let v {
            let radial = (-u + v).normalized
            th = radial.angle
            var t = radial.normalRight
            if t.dot(u + v) < 0 { t = -t }
            ta = t.angle
            ha = M.cornerHandleRatio
        } else {
            let d = (u ?? v)!
            th = lateral(d).angle
            ta = d.angle
            ha = M.straightHandleRatio
        }
        return FiloLoopParams(centre: c, radius: r, apexAngle: th, tangentAngle: ta, handleRatio: ha, tail: 0,
                              entry: u.map { c - $0 * (M.entryDistance * k) + offsetIn }, u: u,
                              exit: v.map { c + $0 * (M.entryDistance * k) + offsetOut }, v: v)
    }

    static func params(_ centres: [FiloVec2], k: Double) -> [FiloLoopParams] {
        let d = directions(centres), o = joinOffsets(centres, k: k)
        return centres.indices.map { i in
            loopParams(centre: centres[i], u: d[i].u, v: d[i].v,
                       offsetIn: i > 0 ? o[i - 1] : .zero,
                       offsetOut: i < o.count ? o[i] : .zero, k: k)
        }
    }

    static func lerpAngle(_ a: Double, _ b: Double, _ t: Double) -> Double { a + wrap(b - a) * t }

    /// Morph p → q. The apex moves along the circle (shortest arc); the
    /// tangent is interpolated RELATIVE to the radius so a loop never sweeps
    /// across the digit. Parts that only exist in q are taken from q (they
    /// are revealed by the draw cutoff).
    static func lerp(_ p: FiloLoopParams, _ q: FiloLoopParams, _ t: Double) -> FiloLoopParams {
        let th = lerpAngle(p.apexAngle, q.apexAngle, t)
        let dp = p.relativeTangent, dq = q.relativeTangent
        var r = q
        r.apexAngle = th
        r.tangentAngle = th + dp + (dq - dp) * t
        r.handleRatio = p.handleRatio + (q.handleRatio - p.handleRatio) * t
        r.tail = p.tail + (q.tail - p.tail) * t
        if let pe = p.entry, let qe = q.entry { r.entry = FiloVec2.lerp(pe, qe, t) }
        if let px = p.exit, let qx = q.exit { r.exit = FiloVec2.lerp(px, qx, t) }
        return r
    }

    /// True when the previous end tile changes the side it turns around its
    /// number (δ changes sign): the renderer crossfades (0.10 s) instead of
    /// sweeping the loop across the digit.
    static func isFlip(_ centres: [FiloVec2], k: Double) -> Bool {
        let n = centres.count
        guard n >= 2 else { return false }
        let old = params(Array(centres.prefix(n - 1)), k: k)[n - 2]
        let new = params(centres, k: k)[n - 2]
        return (old.relativeTangent > 0) != (new.relativeTangent > 0)
    }

    static func controls(_ p: FiloLoopParams) -> FiloLoopControls {
        let m = p.apex, t = FiloVec2.unit(p.tangentAngle)
        var a0 = m, a1 = m, a2 = m
        if let e = p.entry, let u = p.u {
            let h = p.handleRatio * e.distance(m)
            a0 = e; a1 = e + u * h; a2 = m - t * h
        } else if abs(p.tail) > 1e-4 {
            let start = p.apexAngle + p.tail
            let sgn: Double = p.tail > 0 ? -1 : 1
            func tg(_ a: Double) -> FiloVec2 { FiloVec2(-sin(a), cos(a)) * sgn }
            let h = 4.0 / 3.0 * tan(abs(p.tail) / 4) * p.radius
            a0 = p.centre + FiloVec2.unit(start) * p.radius
            a1 = a0 + tg(start) * h
            a2 = m - tg(p.apexAngle) * h
        }
        var b1 = m, b2 = m, b3 = m
        if let x = p.exit, let v = p.v {
            let h = p.handleRatio * x.distance(m)
            b1 = m + t * h; b2 = x - v * h; b3 = x
        }
        return FiloLoopControls(a0: a0, a1: a1, a2: a2, m: m, b1: b1, b2: b2, b3: b3)
    }

    /// Control points for a path; `morph` < 1 interpolates every older tile
    /// from the previous path (count − 1 tiles) to the new one.
    static func loops(_ centres: [FiloVec2], k: Double, morph: Double = 1) -> [FiloLoopControls] {
        var ps = params(centres, k: k)
        if centres.count >= 2 && morph < 1 {
            let old = params(Array(centres.prefix(centres.count - 1)), k: k)
            for i in old.indices { ps[i] = lerp(old[i], ps[i], max(0, morph)) }
        }
        return ps.map(controls)
    }

    // MARK: sampling

    static func cubic(_ p0: FiloVec2, _ p1: FiloVec2, _ p2: FiloVec2, _ p3: FiloVec2, _ t: Double) -> FiloVec2 {
        let m = 1 - t
        let a = m * m * m, b = 3 * m * m * t, c = 3 * m * t * t, d = t * t * t
        return FiloVec2(a * p0.x + b * p1.x + c * p2.x + d * p3.x,
                        a * p0.y + b * p1.y + c * p2.y + d * p3.y)
    }

    /// Dense polyline (24 steps per cubic, links as one segment) + marks.
    static func flatten(_ loops: [FiloLoopControls]) -> (points: [FiloVec2], s: [Double], marks: FiloThreadMarks) {
        var pts: [FiloVec2] = [], ss: [Double] = [], marks = FiloThreadMarks()
        var length = 0.0
        func push(_ p: FiloVec2) {
            if let last = pts.last {
                let d = last.distance(p)
                if d < 1e-6 { return }
                length += d
            }
            pts.append(p); ss.append(length)
        }
        func addCubic(_ a: FiloVec2, _ b: FiloVec2, _ c: FiloVec2, _ d: FiloVec2) {
            if a == b && b == c && c == d { return }
            for i in 1...24 { push(cubic(a, b, c, d, Double(i) / 24)) }
        }
        for lp in loops {
            push(lp.a0)                 // link: straight segment from the previous b3
            marks.entry.append(length)
            addCubic(lp.a0, lp.a1, lp.a2, lp.m)
            marks.apex.append(length)
            addCubic(lp.m, lp.b1, lp.b2, lp.b3)
            marks.exit.append(length)
        }
        return (pts, ss, marks)
    }

    /// Terminal curl (knotted thread): Ø 2·knotRadius, `sweep` radians,
    /// tangent to the tip, on the side of `away` (away from the digit).
    static func appendKnot(points: inout [FiloVec2], s: inout [Double], k: Double,
                           sweep: Double, away: FiloVec2) {
        guard points.count >= 2, sweep > 0 else { return }
        let p = points[points.count - 1], q = points[points.count - 2]
        let t = (p - q).normalized
        var n = t.normalRight
        if n.dot(away) < 0 { n = -n }
        let r = M.knotRadius * k
        let centre = p + n * r
        let a0 = (p - centre).angle
        let dir: Double = FiloVec2(-sin(a0), cos(a0)).dot(t) >= 0 ? 1 : -1
        let steps = max(2, Int((sweep * 180 / .pi / 5).rounded(.up)))
        var length = s.last ?? 0
        for i in 1...steps {
            let a = a0 + dir * sweep * Double(i) / Double(steps)
            let next = centre + FiloVec2.unit(a) * r
            length += points[points.count - 1].distance(next)
            points.append(next); s.append(length)
        }
    }

    /// Uniform arc-length samples (every `step` pt, last one at the end) with
    /// central-difference tangents and normals.
    static func resample(points: [FiloVec2], s: [Double], step: Double = M.step) -> [FiloThreadSample] {
        guard let total = s.last, !points.isEmpty else { return [] }
        var out: [FiloThreadSample] = []
        out.reserveCapacity(Int(total / step) + 2)
        var j = 0
        var d = 0.0
        while true {
            let target = min(d, total)
            while j < points.count - 2 && s[j + 1] < target { j += 1 }
            let a = points[j], b = points[min(j + 1, points.count - 1)]
            let seg = s[min(j + 1, s.count - 1)] - s[j]
            let t = seg > 1e-9 ? (target - s[j]) / seg : 0
            out.append(FiloThreadSample(p: FiloVec2.lerp(a, b, t), s: target, tangent: .zero, normal: .zero))
            if target >= total { break }
            d += step
        }
        for i in out.indices {
            let a = out[max(0, i - 1)].p, b = out[min(out.count - 1, i + 1)].p
            var t = (b - a).normalized
            if t.length < 0.5 { t = FiloVec2(1, 0) }
            out[i].tangent = t
            out[i].normal = t.normalRight
        }
        return out
    }

    /// Full geometry of a thread through `centres` (tile centres, any grid).
    /// - k: tileSide / 72. - morph: see `loops`. - knotSweep: radians of terminal curl (0 = none).
    static func geometry(_ centres: [FiloVec2], k: Double, morph: Double = 1,
                         knotSweep: Double = 0, step: Double = M.step) -> FiloThreadGeometry {
        guard !centres.isEmpty else { return .empty }
        let lp = loops(centres, k: k, morph: morph)
        var flat = flatten(lp)
        if knotSweep > 0, let tip = flat.points.last {
            appendKnot(points: &flat.points, s: &flat.s, k: k, sweep: knotSweep,
                       away: tip - centres[centres.count - 1])
        }
        let samples = resample(points: flat.points, s: flat.s, step: step)
        return FiloThreadGeometry(controls: lp, samples: samples, length: flat.s.last ?? 0, marks: flat.marks)
    }

    // MARK: drawing helpers

    /// Samples up to arc length `cut` (last one interpolated exactly at `cut`).
    static func cut(_ samples: [FiloThreadSample], at cut: Double) -> [FiloThreadSample] {
        var out: [FiloThreadSample] = []
        out.reserveCapacity(samples.count)
        for p in samples {
            if p.s <= cut { out.append(p); continue }
            if let a = out.last, p.s > a.s {
                let t = (cut - a.s) / (p.s - a.s)
                var q = p
                q.p = FiloVec2.lerp(a.p, p.p, t); q.s = cut
                out.append(q)
            }
            break
        }
        return out
    }

    /// Samples in [s0, s1] (ends interpolated).
    static func range(_ samples: [FiloThreadSample], from s0: Double, to s1: Double) -> [FiloThreadSample] {
        let c = cut(samples, at: s1)
        var out: [FiloThreadSample] = []
        for i in c.indices where c[i].s >= s0 {
            if out.isEmpty, i > 0, c[i].s > s0 {
                let a = c[i - 1], t = (s0 - a.s) / (c[i].s - a.s)
                var q = a
                q.p = FiloVec2.lerp(a.p, c[i].p, t); q.s = s0
                out.append(q)
            }
            out.append(c[i])
        }
        return out
    }

    /// Point/tangent at arc length s.
    static func sample(_ samples: [FiloThreadSample], at s: Double) -> FiloThreadSample? {
        guard var a = samples.first else { return nil }
        for b in samples.dropFirst() {
            if b.s >= s {
                let t = b.s > a.s ? max(0, min(1, (s - a.s) / (b.s - a.s))) : 0
                var q = a
                q.p = FiloVec2.lerp(a.p, b.p, t); q.s = s
                return q
            }
            a = b
        }
        return a
    }

    /// Twist: ply offset along the normal at arc length s (phase over the
    /// whole thread). `fray` (0…1) splits the last frayLength pt: the plies
    /// diverge by ±frayAngle from the tip region of a thread of length `total`.
    static func plyOffset(s: Double, sign: Double, k: Double, fray: Double = 0, total: Double = 0) -> Double {
        let phase = 2 * .pi * s / (M.pitch * k)
        var d = sign * M.plyAmplitude * k * sin(phase)
        if fray > 0 {
            let start = total - M.frayLength * k
            if s > start {
                let e = s - start
                d = d * (1 - fray * e / (M.frayLength * k))
                    + sign * tan(M.frayAngleDegrees * .pi / 180) * e * fray
            }
        }
        return d
    }

    /// True where the shadow ply passes in FRONT of the lit one (cos phase < 0).
    static func shadowPlyInFront(s: Double, k: Double) -> Bool {
        cos(2 * .pi * s / (M.pitch * k)) < 0
    }

    /// Deterministic micro-fibres every fibreEvery pt up to `limit`:
    /// (a, b, dark) segments across the body, slanted with the twist.
    static func fibres(_ samples: [FiloThreadSample], k: Double, limit: Double) -> [(a: FiloVec2, b: FiloVec2, dark: Bool)] {
        var out: [(FiloVec2, FiloVec2, Bool)] = []
        let every = M.fibreEvery * k
        guard every > 0, samples.count >= 2 else { return [] }
        var s = every * 0.5, j = 0, i = 0
        while s < limit - 1 {
            while i < samples.count - 2 && samples[i + 1].s < s { i += 1 }
            let a = samples[i], b = samples[i + 1]
            let t = b.s > a.s ? max(0, min(1, (s - a.s) / (b.s - a.s))) : 0
            let p = FiloVec2.lerp(a.p, b.p, t)
            let hash = Double((UInt64(j) &* 2_654_435_761) % 1000) / 1000
            let half = M.fibreHalfLength * k
            let slant = M.fibreSlant * k * (hash < 0.5 ? 1 : -1)
            let p0 = p - a.normal * half - a.tangent * slant
            let p1 = p + a.normal * half + a.tangent * slant
            out.append((p0, p1, j % 3 == 2))
            s += every; j += 1
        }
        return out
    }
}
