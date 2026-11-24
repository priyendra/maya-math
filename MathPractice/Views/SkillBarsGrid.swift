import SwiftUI

/// My progress: skills × levels; each cell is a bar of its mastery points, coloured by value.
struct SkillBarsGrid: View {
    let set: StudySet
    var onSelect: (Concept) -> Void = { _ in }
    @Environment(\.theme) private var theme
    static let levels = ["Basic", "Medium", "Hard"]

    static func points(_ p: SkillProgress?) -> Double {
        100 * min((p?.mastery ?? 0) / ChapterScore.target, 1)
    }

    var body: some View {
        let planner = LearningStore.planner(set)
        let concepts = MasteryGrid.concepts(set)
        let present = Set(set.questions.filter { !$0.isChallenge }.compactMap { q in q.concept.map { "\($0.id)|\(q.difficulty)" } })
        VStack(alignment: .leading, spacing: 14) {
            Text("Your skills").font(theme.font(.section))
            Text("Each bar fills as you earn the level's mastery points; 100 = mastered.")
                .font(theme.font(.caption)).foregroundStyle(.secondary)
            Grid(alignment: .center, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    ForEach(Self.levels, id: \.self) { l in
                        Text(l).font(theme.font(.label)).foregroundStyle(.secondary).frame(width: 150)
                    }
                    Text("")
                }
                ForEach(concepts) { c in
                    Divider().gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        Text(MathPlain.render(c.name)).font(theme.font(.body))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(1...3, id: \.self) { d in
                            let key = CellKey(conceptID: c.id, conceptOrder: c.bookOrder, difficulty: d)
                            let p = planner.skills[key]
                            BarCell(has: present.contains("\(c.id)|\(d)"), open: planner.isOpen(key), tried: (p?.attemptCount ?? 0) > 0,
                                    points: Self.points(p), mastered: planner.isMastered(key))
                                .frame(width: 150)
                        }
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(c) }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("skill-\(c.bookOrder)")
                }
            }
        }
    }
}

/// A progress bar per level, coloured by its points: red (low) → amber → yellow-green; green once mastered.
struct BarCell: View {
    let has: Bool
    let open: Bool
    let tried: Bool
    let points: Double
    let mastered: Bool
    @Environment(\.theme) private var theme

    static func color(_ points: Double, mastered: Bool) -> Color {
        if mastered { return Color(hue: 0.38, saturation: 0.75, brightness: 0.72) }
        let t = min(max(points / 100, 0), 1)
        return Color(hue: 0.0 + 0.24 * t, saturation: 0.8, brightness: 0.9 - 0.08 * t)
    }

    var body: some View {
        if !has {
            Text("—").foregroundStyle(.tertiary).frame(height: 30)
        } else {
            let c = Self.color(points, mastered: mastered)
            HStack(spacing: 8) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(open || tried ? 0.15 : 0.07))
                        Capsule().fill(c).frame(width: g.size.width * points / 100)
                    }
                }
                .frame(height: 12)
                Group {
                    if mastered { Image(systemName: "star.fill").foregroundStyle(c) }
                    else if !open && !tried { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
                    else if tried { Text("\(Int(points.rounded()))").foregroundStyle(c) }
                    else { Text("0").foregroundStyle(.tertiary) }
                }
                .font(theme.font(.label).monospacedDigit().weight(.semibold))
                .frame(width: 30, alignment: .trailing)
            }
            .frame(height: 30)
        }
    }
}
