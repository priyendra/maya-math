import SwiftUI
import UIKit

/// One question with her answers to it (newest first). Each answer opens the answer page.
struct QuestionAnswersCard: View {
    let question: Question
    let attempts: [Attempt]
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MathText(markdown: question.text, fontSize: 17)
            ChapterLink(question: question)
            if let fig = question.figureData, let img = UIImage(data: fig) {
                Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 140)
            }
            if attempts.isEmpty {
                Text("You haven't answered this one yet.").font(theme.font(.caption)).foregroundStyle(.secondary)
            }
            ForEach(attempts) { a in
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    NavigationLink { AttemptReviewView(attempt: a) } label: {
                        HStack(spacing: 10) {
                            if a.isGraded { VerdictBadge(verdict: a.effectiveVerdict).font(.title3) } else { ProgressView() }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.isGraded ? a.effectiveVerdict.label : "Being checked").font(theme.font(.label).weight(.semibold))
                                Text(a.startedAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute())
                                     + " · " + ProgressSummaryBar.duration(a.activeSeconds)
                                     + (a.isGraded && a.effectiveVerdict == .incorrect ? (a.mistakeType.map { " · \($0.displayName)" } ?? "") : "")
                                     + (a.gradingError != nil && !a.isGraded ? " · waiting to retry" : ""))
                                    .font(theme.font(.caption)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let data = a.renderedImage, let img = UIImage(data: data) {
                                Image(uiImage: img).resizable().scaledToFit()
                                    .frame(maxWidth: 340, maxHeight: 130)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
                            }
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if a.effectiveVerdict == .incorrect, a.correction == nil, !a.errorStep.isEmpty {
                        MathText(markdown: a.errorStep, fontSize: 15)
                    }
                }
            }
        }
        .padding(18)
        .card(theme)
    }
}


/// "See in chapter": the exercise's place in the book (for a generated question, the exercise it was made from).
struct ChapterLink: View {
    let question: Question
    @Environment(\.theme) private var theme

    var body: some View {
        let chapter = question.chapter
        let base = question.parentQuestionID.flatMap { id in chapter?.questions.first { $0.id == id } } ?? question
        if let chapter {
            NavigationLink { ReadChapterView(chapter: chapter, focus: base) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "book")
                    Text(Self.label(question: question, base: base))
                }
                .font(theme.font(.caption).weight(.semibold))
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("seeInChapter")
        }
    }

    static func label(question: Question, base: Question) -> String {
        var place = base.printedNumber.isEmpty ? "the exercise" : "exercise \(base.printedNumber)"
        if let page = base.printedPage { place += ", page \(page)" }
        return base.id == question.id ? "See in chapter · \(place)" : "Made from \(place) · See in chapter"
    }
}

/// What the answers list shows: by skill, level and mistake type, newest or oldest first.
struct AnswerFilter: Equatable {
    var conceptID: UUID?
    var level: Int?
    var mistake: MistakeType?
    var newestFirst = true

    func matches(_ a: Attempt) -> Bool {
        guard let q = a.question else { return false }
        if let conceptID, q.concept?.id != conceptID { return false }
        if let level, q.difficulty != level { return false }
        if let mistake {
            guard a.isGraded, a.effectiveVerdict == .incorrect, a.mistakeType == mistake else { return false }
        }
        return true
    }

    /// One card per question with a matching answer; the card shows all her answers to it.
    /// Ordered by the question's latest matching answer (newest first) or its first one (oldest first).
    func cards(_ attempts: [Attempt]) -> [(Question, [Attempt])] {
        var keyDate: [UUID: Date] = [:]
        var questions: [UUID: Question] = [:]
        for a in attempts where matches(a) {
            guard let q = a.question else { continue }
            questions[q.id] = q
            let d = a.startedAt
            if let old = keyDate[q.id] { keyDate[q.id] = newestFirst ? max(old, d) : min(old, d) } else { keyDate[q.id] = d }
        }
        let ids = Set(questions.keys)
        var answers: [UUID: [Attempt]] = [:]
        for a in attempts { if let id = a.question?.id, ids.contains(id) { answers[id, default: []].append(a) } }
        let order = Self.order(keyDate, newestFirst: newestFirst)
        return order.compactMap { id in
            questions[id].map { q in
                (q, (answers[id] ?? []).sorted { newestFirst ? $0.startedAt > $1.startedAt : $0.startedAt < $1.startedAt })
            }
        }
    }

    static func order(_ keyDate: [UUID: Date], newestFirst: Bool) -> [UUID] {
        keyDate.sorted { newestFirst ? $0.value > $1.value : $0.value < $1.value }.map(\.key)
    }
}

/// The one way answers are shown: My answers, a skill's page and a mistake's page all use it,
/// starting from different filters. My answers also pins what needs her (to check, still being checked).
struct AnswersBrowser<Header: View>: View {
    let set: StudySet
    var showInbox = false
    @State var filter: AnswerFilter
    @ViewBuilder var header: () -> Header
    @Environment(\.theme) private var theme
    @ObservedObject private var grading = GradingQueue.shared

    var body: some View {
        let _ = grading.version
        let all = set.allAttempts
        let cards = filter.cards(all)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                header()
                if showInbox { inbox(all) }
                AnswerFilterBar(set: set, filter: $filter)
                Text(cards.isEmpty ? "No answers match." : "\(cards.count) question\(cards.count == 1 ? "" : "s")")
                    .font(theme.font(.caption)).foregroundStyle(.secondary)
                ForEach(cards, id: \.0.id) { q, answers in
                    QuestionAnswersCard(question: q, attempts: answers)
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func inbox(_ all: [Attempt]) -> some View {
        let toCheck = all.filter { $0.isGraded && $0.effectiveVerdict == .needsReview }.sorted { $0.startedAt > $1.startedAt }
        let pending = all.filter { !$0.isGraded }
        if !toCheck.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("To check (\(toCheck.count))").font(theme.font(.section))
                Text("Claude wasn't sure how to grade these. Open one and decide whether your answer was right, or grade it again.")
                    .font(theme.font(.caption)).foregroundStyle(.secondary)
            }
            ForEach(AnswerFilter().cards(toCheck), id: \.0.id) { q, answers in
                QuestionAnswersCard(question: q, attempts: answers)
            }
        }
        if !pending.isEmpty {
            Text("Still being checked: \(pending.count) answer\(pending.count == 1 ? "" : "s"). They'll appear below when graded.")
                .font(theme.font(.caption)).foregroundStyle(.secondary)
        }
        if !toCheck.isEmpty || !pending.isEmpty {
            Text("All answers").font(theme.font(.section)).padding(.top, 8)
        }
    }
}

struct AnswerFilterBar: View {
    let set: StudySet
    @Binding var filter: AnswerFilter
    @Environment(\.theme) private var theme

    var body: some View {
        let concepts = MasteryGrid.concepts(set)
        HStack(spacing: 10) {
            chip(icon: "square.grid.2x2") {
                Picker("Skill", selection: $filter.conceptID) {
                    Text("All skills").tag(UUID?.none)
                    ForEach(concepts) { c in Text(MathPlain.render(c.name)).tag(Optional(c.id)) }
                }
            }
            chip(icon: "chart.bar") {
                Picker("Level", selection: $filter.level) {
                    Text("All levels").tag(Int?.none)
                    ForEach(1...3, id: \.self) { d in Text(SkillBarsGrid.levels[d - 1]).tag(Optional(d)) }
                }
            }
            chip(icon: "exclamationmark.triangle") {
                Picker("Mistake", selection: $filter.mistake) {
                    Text("All answers").tag(MistakeType?.none)
                    ForEach(MistakeType.allCases, id: \.self) { m in Text(m.displayName).tag(Optional(m)) }
                }
            }
            chip(icon: "arrow.up.arrow.down") {
                Picker("Order", selection: $filter.newestFirst) {
                    Text("Newest first").tag(true)
                    Text("Oldest first").tag(false)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func chip<C: View>(icon: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon).foregroundStyle(.secondary).font(.caption)
            content().pickerStyle(.menu).lineLimit(1)
        }
        .padding(.leading, 10).padding(.trailing, 2)
        .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
        .frame(maxWidth: 300)
    }
}

/// A skill's page: its points and what each level needs, then its answers (filters start on this skill).
struct SkillDetailView: View {
    let set: StudySet
    let concept: Concept
    @Environment(\.theme) private var theme

    var body: some View {
        AnswersBrowser(set: set, filter: AnswerFilter(conceptID: concept.id)) { header }
            .navigationTitle(MathPlain.render(concept.name))
    }

    private var header: some View {
        let planner = LearningStore.planner(set)
        let questions = set.questions.filter { $0.concept?.id == concept.id && !$0.isChallenge }
        let levels = (1...3).filter { d in questions.contains { $0.difficulty == d } }
        let cells = levels.map { CellKey(conceptID: concept.id, conceptOrder: concept.bookOrder, difficulty: $0) }
        let skillPoints = cells.isEmpty ? 0 : cells.map { SkillBarsGrid.points(planner.skills[$0]) }.reduce(0, +) / Double(cells.count)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(Int(skillPoints.rounded()))").font(.system(size: 34, weight: .bold, design: theme.design).monospacedDigit())
                Text("of 100 mastery points for this skill").font(theme.font(.label)).foregroundStyle(.secondary)
            }
            ForEach(levels, id: \.self) { d in
                let key = CellKey(conceptID: concept.id, conceptOrder: concept.bookOrder, difficulty: d)
                let p = planner.skills[key]
                let open = planner.isOpen(key), mastered = planner.isMastered(key)
                HStack(spacing: 14) {
                    Text(SkillBarsGrid.levels[d - 1]).font(theme.font(.label).weight(.semibold)).frame(width: 80, alignment: .leading)
                    BarCell(has: true, open: open, tried: (p?.attemptCount ?? 0) > 0, points: SkillBarsGrid.points(p), mastered: mastered)
                        .frame(width: 200)
                    Text(Self.levelLine(p: p, open: open, mastered: mastered, level: d,
                                        estimate: Self.median(questions.filter { $0.difficulty == d }.map { Double($0.estimatedSeconds) })))
                        .font(theme.font(.body)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .card(theme)
    }

    static func median(_ xs: [Double]) -> Double {
        let s = xs.sorted()
        guard !s.isEmpty else { return 120 }
        return s.count.isMultiple(of: 2) ? (s[s.count / 2 - 1] + s[s.count / 2]) / 2 : s[s.count / 2]
    }

    static func levelLine(p: SkillProgress?, open: Bool, mastered: Bool, level: Int, estimate: Double) -> String {
        if mastered { return "Mastered ★ — a review question now and then." }
        guard let p, p.attemptCount > 0 else {
            return open ? "Not started yet." : "Opens at 75 points on \(SkillBarsGrid.levels[max(0, level - 2)])."
        }
        if MasteryModel.heldBackBySpeed(p, estimate: estimate) {
            return "Getting these right — now a little quicker for the ★."
        }
        let n = MasteryModel.rightAnswersToStar(p)
        return "\(n) more right in a row to master."
    }
}

/// A mistake type's page: what it means, then the answers (filters start on this mistake).
struct MistakeDetailView: View {
    let set: StudySet
    let mistake: MistakeType
    @Environment(\.theme) private var theme

    static func meaning(_ m: MistakeType) -> String {
        switch m {
        case .incomplete: return "You stopped before the final answer."
        case .procedural: return "A step in the method went wrong."
        case .careless: return "A small slip: a sign, an arithmetic step, or copying a number."
        case .conceptual: return "The idea behind a step was off. Worth re-reading that part of the chapter."
        case .misread: return "The question asked for something different from what you answered."
        }
    }

    var body: some View {
        AnswersBrowser(set: set, filter: AnswerFilter(mistake: mistake)) {
            Text(Self.meaning(mistake)).font(theme.font(.body)).foregroundStyle(.secondary)
        }
        .navigationTitle(mistake.displayName)
    }
}
