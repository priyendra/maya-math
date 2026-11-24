import SwiftUI

/// What one skill cell shows: a stage (colour + name) and dots toward the star.
struct SkillCellLook {
    let stage: SkillStage
    let dots: Int
    let toStar: Int
    /// Enough right answers for the star, but slower than expected.
    let slow: Bool

    init(progress p: SkillProgress, mastered: Bool, estimate: Double) {
        stage = SkillStage.of(p, mastered: mastered)
        dots = MasteryModel.dots(p.mastery)
        toStar = MasteryModel.rightAnswersToStar(p)
        slow = !mastered && p.attemptCount > 0 && MasteryModel.heldBackBySpeed(p, estimate: estimate)
    }

    var spoken: String {
        switch stage {
        case .new: return "Not started yet"
        case .mastered: return "Mastered"
        default:
            if slow { return "\(stage.name), right enough for the star, now a bit faster" }
            return "\(stage.name), \(dots) of \(MasteryModel.steps) steps, \(toStar) more right in a row for the star"
        }
    }
}

/// Dots (or star / Ready) drawn inside a coloured skill cell.
struct SkillCellContent: View {
    let look: SkillCellLook
    @Environment(\.theme) private var theme

    var body: some View {
        let ink = theme.skillInk(look.stage)
        switch look.stage {
        case .new:
            SkillDots(filled: 0, color: theme.learn)
        case .mastered:
            Image(systemName: "star.fill").font(.headline).foregroundStyle(.white)
        default:
            HStack(spacing: 6) {
                SkillDots(filled: look.dots, color: ink)
                if look.slow { Image(systemName: "timer").font(.system(size: 13, weight: .bold)).foregroundStyle(ink) }
            }
        }
    }
}

struct SkillDots: View {
    let filled: Int
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        HStack(spacing: size * 0.5) {
            ForEach(0..<MasteryModel.steps, id: \.self) { i in
                Circle()
                    .fill(i < filled ? color : .clear)
                    .overlay(Circle().strokeBorder(color.opacity(i < filled ? 0 : 0.6), lineWidth: 1.5))
                    .frame(width: size, height: size)
            }
        }
    }
}

/// "Your skills": summary bar, grid, legend and a "How this works" explanation.
struct SkillsPanel: View {
    let set: StudySet
    var testDate: Date? = nil
    var title = "Your skills"
    @Environment(\.theme) private var theme
    @State private var showHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title).font(theme.font(.section))
                Spacer()
                Button { showHelp = true } label: { Label("How this works", systemImage: "info.circle") }
                    .font(theme.font(.label))
                    .popover(isPresented: $showHelp) { SkillsHelpView().frame(width: 460) }
            }
            ProgressSummaryBar(set: set, testDate: testDate)
            MasteryGrid(set: set)
            SkillLegend()
        }
    }
}

/// Answered, right, time, skills, review due, days to test; plus "answers to check".
struct ProgressSummaryBar: View {
    let set: StudySet
    var testDate: Date? = nil
    /// Chapter page: answered, right, mastered only.
    var compact = false
    @Environment(\.theme) private var theme

    var body: some View {
        let attempts = set.allAttempts
        let answers = attempts.map { a in
            ProgressSummary.Answer(
                date: a.startedAt,
                counted: a.isGraded && a.effectiveVerdict != .needsReview
                    && !(a.question?.isChallenge == true && a.effectiveVerdict == .incorrect),
                correct: a.effectiveVerdict == .correct,
                seconds: a.activeSeconds)
        }
        let s = ProgressSummary(answers: answers, planner: LearningStore.planner(set))
        let toCheck = attempts.filter { $0.isGraded && $0.effectiveVerdict == .needsReview }.count
        if s.answered > 0 || testDate != nil || toCheck > 0 {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    if let testDate { tile(Self.daysLeft(testDate), "days to the test", icon: "calendar") }
                    tile("\(s.answered)", s.answeredToday > 0 ? "answered · \(s.answeredToday) today" : "answered")
                    if let acc = s.accuracy {
                        tile(Self.percent(acc), s.accuracyToday.map { "right · \(Self.percent($0)) today" } ?? "right")
                    }
                    if !compact { tile(Self.duration(s.seconds), s.days == 1 ? "practice · 1 day" : "practice · \(s.days) days") }
                    tile("\(s.masteredCells) of \(s.totalCells)", "mastered · \(s.almostCells) almost", icon: "star.fill")
                    if s.masteredCells > 0 && !compact {
                        tile("\(s.reviewDueToday)", s.reviewDueTomorrow > 0 ? "to review today · \(s.reviewDueTomorrow) tomorrow" : "to review today",
                             icon: "arrow.clockwise")
                    }
                }
                if toCheck > 0 {
                    NavigationLink { MyAnswersView(set: set) } label: {
                        Label(toCheck == 1 ? "1 answer to check" : "\(toCheck) answers to check", systemImage: "questionmark.circle.fill")
                            .font(theme.font(.label)).foregroundStyle(theme.attention)
                    }
                }
            }
        }
    }

    private func tile(_ value: String, _ label: String, icon: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(.secondary) }
                Text(value).font(.system(size: 24, weight: .bold, design: theme.design).monospacedDigit())
            }
            Text(label).font(theme.font(.caption)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: min(theme.radius * 0.6, 10), style: .continuous))
    }

    static func percent(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }

    static func duration(_ seconds: Double) -> String {
        let m = Int(seconds / 60)
        return m < 60 ? "\(m) min" : "\(m / 60) h \(m % 60) m"
    }

    static func daysLeft(_ date: Date) -> String {
        let cal = Calendar.current
        let d = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: date)).day ?? 0
        return "\(max(d, 0))"
    }
}

/// One row naming each cell look.
struct SkillLegend: View {
    @Environment(\.theme) private var theme

    var body: some View {
        let items: [(String, SkillStage?, Int)] = [("Not started", .new, 0), ("Learning", .learning, 1), ("Getting there", .gettingThere, 2),
                                                   ("Almost", .almost, 4), ("Mastered", .mastered, 5), ("Locked", nil, 0)]
        HStack(spacing: 16) {
            ForEach(items, id: \.0) { name, stage, dots in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(stage.map { theme.skillColor($0) } ?? Color.secondary.opacity(0.13))
                        .frame(width: 34, height: 20)
                        .overlay {
                            switch stage {
                            case nil: Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                            case .mastered: Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.white)
                            case .new: SkillDots(filled: 0, color: theme.learn, size: 4)
                            case let s?: SkillDots(filled: dots, color: theme.skillInk(s), size: 4)
                            }
                        }
                    Text(name).font(theme.font(.caption)).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Plain explanation of the grid, in second person.
struct SkillsHelpView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("How your skills work").font(theme.font(.section))
                para("square.grid.3x3.fill", "Each square is one skill at one level: Basic, Medium or Hard.")
                para("circle.fill", "The dots are steps toward a star. Each right answer fills in a dot. Five right in a row from a fresh start earns the star ★.")
                para("arrow.uturn.down", "A wrong answer takes away about half your dots. A careless slip takes away fewer.")
                para("timer", "A timer means you're right often enough for the star — now try to be a bit quicker.")
                para("lock.fill", "Medium and Hard open once the level below is yellow (Almost). If the level below slips back, the level above locks again until you bring it back up — your dots there are kept.")
                para("arrow.clockwise", "Skills with a star come back for a quick review after 1, 3, 7 and then 14 days, so you keep them.")
                para("paintpalette.fill", "Colours: light blue = not started yet, rose = learning, orange = getting there, yellow = almost, green ★ = mastered.")
            }
            .padding(24)
        }
    }

    private func para(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon).foregroundStyle(theme.accent).frame(width: 22)
            Text(text).font(theme.font(.body)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
