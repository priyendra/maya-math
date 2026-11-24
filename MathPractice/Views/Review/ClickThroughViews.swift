import SwiftUI
import UIKit

// MARK: - Filter

/// Which answers to show by result: all, right ones, any mistake, or one kind of mistake.
enum ResultFilter: Hashable {
    case all, right, anyMistake
    case mistake(MistakeType)

    var label: String {
        switch self {
        case .all: return "All answers"
        case .right: return "Correct answers"
        case .anyMistake: return "Wrong answers"
        case .mistake(let m): return m.displayName
        }
    }

    static var main: [ResultFilter] { [.all, .right, .anyMistake] }
}

/// What the answers list shows: by skill, level and result, newest or oldest first.
struct AnswerFilter: Equatable {
    var conceptID: UUID?
    var level: Int?
    var result: ResultFilter = .all
    var newestFirst = true

    func matches(_ a: Attempt) -> Bool {
        guard let q = a.question else { return false }
        if let conceptID, q.concept?.id != conceptID { return false }
        if let level, q.difficulty != level { return false }
        switch result {
        case .all: return true
        case .right: return a.isGraded && a.effectiveVerdict == .correct
        case .anyMistake: return a.isGraded && a.effectiveVerdict == .incorrect
        case .mistake(let m): return a.isGraded && a.effectiveVerdict == .incorrect && a.mistakeType == m
        }
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
        var answers: [UUID: [Attempt]] = [:]
        for a in attempts { if let id = a.question?.id, questions[id] != nil { answers[id, default: []].append(a) } }
        return Self.order(keyDate, newestFirst: newestFirst).compactMap { id in
            questions[id].map { q in
                (q, (answers[id] ?? []).sorted { newestFirst ? $0.startedAt > $1.startedAt : $0.startedAt < $1.startedAt })
            }
        }
    }

    static func order(_ keyDate: [UUID: Date], newestFirst: Bool) -> [UUID] {
        keyDate.sorted { newestFirst ? $0.value > $1.value : $0.value < $1.value }.map(\.key)
    }
}

// MARK: - Browser

/// The one way answers are shown: My answers, a skill's page and a mistake's page all use it,
/// starting from different filters. My answers also pins what needs her (to check, still being checked).
struct AnswersBrowser<Header: View>: View {
    let set: StudySet
    var showInbox = false
    @State var filter: AnswerFilter
    @ViewBuilder var header: () -> Header
    @State private var shown = Self.page
    @Environment(\.theme) private var theme
    @ObservedObject private var grading = GradingQueue.shared

    static var page: Int { 25 }

    var body: some View {
        let _ = grading.version
        let all = set.allAttempts
        let cards = filter.cards(all)
        ScrollView {
            // Cards use native text (MathPlainText), not web views: dozens of web views made scrolling stutter and jump.
            LazyVStack(alignment: .leading, spacing: 14) {
                header()
                if showInbox { inbox(all) }
                AnswerFilterBar(set: set, filter: $filter, count: cards.count)
                    .padding(.top, 4)
                if cards.isEmpty {
                    Text("No answers match these filters.")
                        .font(theme.font(.body)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                }
                ForEach(cards.prefix(shown), id: \.0.id) { q, answers in
                    QuestionAnswersCard(question: q, attempts: answers)
                }
                if cards.count > shown {
                    Button { shown += Self.page } label: {
                        Text("Show \(min(Self.page, cards.count - shown)) more of \(cards.count - shown)")
                            .font(theme.font(.label).weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered).buttonBorderShape(.capsule)
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .onChange(of: filter) { shown = Self.page }
    }

    @ViewBuilder
    private func inbox(_ all: [Attempt]) -> some View {
        let toCheck = all.filter { $0.isGraded && $0.effectiveVerdict == .needsReview }
        let pending = all.filter { !$0.isGraded }
        if !toCheck.isEmpty {
            SectionTitle(title: "To check", count: toCheck.count,
                         note: "Claude wasn't sure how to grade these. Open one to decide, or grade it again.")
            ForEach(AnswerFilter().cards(toCheck), id: \.0.id) { q, answers in
                QuestionAnswersCard(question: q, attempts: answers)
            }
        }
        if !pending.isEmpty {
            Label("\(pending.count) answer\(pending.count == 1 ? " is" : "s are") still being checked", systemImage: "hourglass")
                .font(theme.font(.caption)).foregroundStyle(.secondary)
        }
        if !toCheck.isEmpty {
            SectionTitle(title: "All answers", count: nil, note: nil).padding(.top, 10)
        }
    }
}

private struct SectionTitle: View {
    let title: String
    let count: Int?
    let note: String?
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title).font(theme.font(.section))
                if let count {
                    Text("\(count)").font(theme.font(.label).weight(.bold).monospacedDigit())
                        .padding(.horizontal, 9).padding(.vertical, 2)
                        .background(Capsule().fill(theme.attention.opacity(0.18)))
                        .foregroundStyle(theme.attention)
                }
            }
            if let note { Text(note).font(theme.font(.caption)).foregroundStyle(.secondary) }
        }
    }
}

// MARK: - Filter bar

struct AnswerFilterBar: View {
    let set: StudySet
    @Binding var filter: AnswerFilter
    let count: Int
    @Environment(\.theme) private var theme

    var body: some View {
        let concepts = set.concepts
        HStack(spacing: 8) {
            Menu {
                Section {
                    ForEach(ResultFilter.main, id: \.self) { r in choice(r) }
                }
                Section("Mistake categories") {
                    ForEach(MistakeType.allCases, id: \.self) { m in choice(.mistake(m)) }
                }
            } label: {
                MenuPill(icon: "line.3.horizontal.decrease", text: filter.result.label, active: filter.result != .all, menu: true)
                    .fixedSize()
            }
            .layoutPriority(2)
            .accessibilityIdentifier("resultFilter")
            Menu {
                Picker("Skill", selection: $filter.conceptID) {
                    Text("All skills").tag(UUID?.none)
                    ForEach(concepts) { c in Text(MathPlain.render(c.name)).tag(Optional(c.id)) }
                }
            } label: {
                let name = concepts.first { $0.id == filter.conceptID }.map { MathPlain.render($0.name) }
                MenuPill(icon: "square.grid.2x2", text: name ?? "All skills", active: name != nil, menu: true)
            }
            Menu {
                Picker("Level", selection: $filter.level) {
                    Text("All levels").tag(Int?.none)
                    ForEach(1...3, id: \.self) { d in Text(SkillBarsGrid.levels[d - 1]).tag(Optional(d)) }
                }
            } label: {
                MenuPill(icon: "chart.bar", text: filter.level.map { SkillBarsGrid.levels[$0 - 1] } ?? "All levels",
                         active: filter.level != nil, menu: true)
                    .fixedSize()
            }
            .layoutPriority(2)
            Spacer(minLength: 8)
            Text("\(count) question\(count == 1 ? "" : "s")").font(theme.font(.caption).monospacedDigit()).foregroundStyle(.secondary)
                .fixedSize()
            Button { filter.newestFirst.toggle() } label: {
                MenuPill(icon: filter.newestFirst ? "arrow.down" : "arrow.up",
                         text: filter.newestFirst ? "Newest first" : "Oldest first", active: false)
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sortOrder")
        }
    }
}

extension AnswerFilterBar {
    /// A menu item that selects a result filter, ticked when it's the current one.
    fileprivate func choice(_ r: ResultFilter) -> some View {
        Button { filter.result = r } label: {
            if filter.result == r { Label(r.label, systemImage: "checkmark") } else { Text(r.label) }
        }
    }
}

private struct MenuPill: View {
    let icon: String
    let text: String
    let active: Bool
    var menu = false
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.subheadline.weight(.semibold))
            Text(text).lineLimit(1).truncationMode(.tail).frame(maxWidth: 320, alignment: .leading)
            if menu { Image(systemName: "chevron.down").font(.caption.weight(.bold)) }
        }
        .font(theme.font(.label).weight(.semibold))
        .padding(.horizontal, 16).padding(.vertical, 11)
        .frame(minHeight: 44)
        .background(Capsule().fill(active ? theme.accent : Color(.secondarySystemGroupedBackground)))
        .overlay(Capsule().stroke(active ? Color.clear : Color.secondary.opacity(0.22)))
        .foregroundStyle(active ? Color.white : Color.primary)
        .shadow(color: .black.opacity(active ? 0.12 : 0.04), radius: 3, y: 1)
        .contentShape(Capsule())
    }
}

// MARK: - Card

/// One question with her answers to it. Each answer opens the answer page.
struct QuestionAnswersCard: View {
    let question: Question
    let attempts: [Attempt]
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(SkillBarsGrid.levels[max(0, min(2, question.difficulty - 1))].uppercased())
                    .font(.system(size: 11, weight: .bold)).tracking(0.6)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(theme.accent.opacity(0.12)))
                    .foregroundStyle(theme.accent)
                if let c = question.concept {
                    Text(MathPlain.render(c.name)).font(theme.font(.caption)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                ChapterLink(question: question)
            }
            MathPlainText(markdown: question.text).font(.system(size: 18)).fixedSize(horizontal: false, vertical: true)
            if let fig = question.figureData, let img = UIImage(data: fig) {
                Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 140)
            }
            if attempts.isEmpty {
                Text("You haven't answered this one yet.").font(theme.font(.caption)).foregroundStyle(.secondary)
            }
            VStack(spacing: 8) {
                ForEach(attempts) { a in AnswerRow(attempt: a) }
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

private struct AnswerRow: View {
    let attempt: Attempt
    @Environment(\.theme) private var theme

    var body: some View {
        let a = attempt
        let tone: Color = !a.isGraded ? .secondary
            : a.effectiveVerdict == .correct ? theme.done : a.effectiveVerdict == .incorrect ? theme.notQuite : theme.attention
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink { AttemptReviewView(attempt: a) } label: {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(!a.isGraded ? "Being checked" : a.effectiveVerdict.label)
                                .font(theme.font(.label).weight(.bold)).foregroundStyle(tone)
                            if a.isGraded, a.effectiveVerdict == .incorrect, let m = a.mistakeType {
                                Text(m.displayName).font(theme.font(.caption).weight(.semibold))
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(Capsule().fill(tone.opacity(0.12))).foregroundStyle(tone)
                            }
                        }
                        Text(a.startedAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                             + " · " + Fmt.duration(a.activeSeconds)
                             + (a.gradingError != nil && !a.isGraded ? " · waiting to retry" : ""))
                            .font(theme.font(.caption)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if let data = a.renderedImage, let img = UIImage(data: data) {
                        Image(uiImage: img).resizable().scaledToFit()
                            .frame(width: 300, height: 150)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.secondary.opacity(0.15)))
                    }
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if a.isGraded, a.effectiveVerdict == .incorrect, a.correction == nil, !a.errorStep.isEmpty {
                MathPlainText(markdown: a.errorStep).font(.system(size: 15))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.notQuite.opacity(0.07)))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.systemGroupedBackground)))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12, style: .continuous)
                .fill(tone).frame(width: 4)
        }
    }
}

/// The exercise's place in the book (for a generated question, the exercise it was made from).
struct ChapterLink: View {
    let question: Question
    @Environment(\.theme) private var theme

    var body: some View {
        let chapter = question.chapter
        let base = question.parentQuestionID.flatMap { id in chapter?.questions.first { $0.id == id } } ?? question
        if let chapter {
            NavigationLink { ReadChapterView(chapter: chapter, focus: base) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "book.pages")
                    Text(Self.label(question: question, base: base))
                }
                .font(theme.font(.caption).weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(theme.accent.opacity(0.10)))
                .foregroundStyle(theme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("seeInChapter")
        }
    }

    static func label(question: Question, base: Question) -> String {
        var place = base.printedNumber.isEmpty ? "In chapter" : "Ex. \(base.printedNumber)"
        if let page = base.printedPage { place += " · p. \(page)" }
        return base.id == question.id ? place : "From " + place.replacingOccurrences(of: "Ex.", with: "ex.")
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
                    Text(Self.levelLine(p: p, open: open, mastered: mastered, level: d))
                        .font(theme.font(.body)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .card(theme)
    }

    static func levelLine(p: SkillProgress?, open: Bool, mastered: Bool, level: Int) -> String {
        if mastered { return "Mastered — a review question now and then." }
        guard let p, p.attemptCount > 0 else {
            return open ? "Not started yet." : "Opens at 75 points on \(SkillBarsGrid.levels[max(0, level - 2)])."
        }
        let n = MasteryModel.rightAnswersToMaster(p)
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
        AnswersBrowser(set: set, filter: AnswerFilter(result: .mistake(mistake))) {
            Text(Self.meaning(mistake)).font(theme.font(.body)).foregroundStyle(.secondary)
        }
        .navigationTitle(mistake.displayName)
    }
}
