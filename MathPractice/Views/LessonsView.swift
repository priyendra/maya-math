import SwiftUI
import SwiftData

/// The chapter as a table of lessons: each lesson is one unit of the book, taught in parts. Together they cover the
/// chapter's core material; what's left out is listed (with why) at the bottom.
struct LessonsView: View {
    @Bindable var chapter: Chapter
    @Environment(\.modelContext) private var context
    @Environment(\.theme) private var theme
    @State private var open: Lesson?
    @State private var expanded: Set<UUID> = []
    @State private var planning = false
    @State private var planError: String?
    @State private var showSkipped = false

    var body: some View {
        let lessons = chapter.sortedLessons
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if lessons.isEmpty {
                    prepareCard
                } else {
                    if let next = continueLesson(lessons) { continueCard(next) }
                    VStack(spacing: 0) {
                        ForEach(Array(lessons.enumerated()), id: \.element.id) { i, l in
                            row(l, number: lessons.first?.optional == true ? i : i + 1)  // a warm-up lesson is number 0
                            if i < lessons.count - 1 { Divider().padding(.leading, 56) }
                        }
                    }
                    .card(theme)
                    skippedList
                    Button("Plan the lessons again") { plan() }
                        .font(.caption).foregroundStyle(.secondary).disabled(planning)
                }
            }
            .padding(24)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .themedBackground(theme)
        .navigationTitle("Lessons")
        .fullScreenCover(item: $open) { l in LessonPage(lesson: l, onNext: { next in open = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { open = next } }) }
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-openLesson"), open == nil { open = lessons.first }
        }
        #endif
    }

    // MARK: Pieces

    private var prepareCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Learn this chapter, one lesson at a time", systemImage: "graduationcap.fill").font(theme.font(.section)).foregroundStyle(theme.learn)
            Text("A tutor walks you through each part of the chapter out loud, with the book's examples, then gives you one to try. Ask a question any time.")
                .foregroundStyle(.secondary)
            if planning {
                HStack { ProgressView(); Text("Planning the lessons… (about a minute)") }
            } else {
                Button { plan() } label: { Label("Prepare lessons", systemImage: "sparkles") }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
            if let planError { Text(planError).font(.callout).foregroundStyle(.red) }
        }
        .padding(20)
        .card(theme, tint: theme.learn)
    }

    private func continueCard(_ l: Lesson) -> some View {
        Button { open = l } label: {
            HStack(spacing: 14) {
                Image(systemName: "play.circle.fill").font(.system(size: 40))
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.status == .inProgress ? "Continue: \(MathPlain.render(l.title))" : "Start: \(MathPlain.render(l.title))").font(theme.font(.cardTitle))
                    Text(l.status == .inProgress ? "Part \(l.partsDone + 1) of \(l.parts.count)" : "\(l.parts.count) part\(l.parts.count == 1 ? "" : "s") · about \(minutes(l)) min")
                        .font(theme.font(.label)).opacity(0.9)
                }
                Spacer()
            }
            .padding(18)
            .foregroundStyle(.white)
            .background(theme.fill(theme.learn), in: RoundedRectangle(cornerRadius: theme.radius, style: .continuous))
            .shadow(color: theme.shadow ? theme.learn.opacity(0.3) : .clear, radius: 10, y: 5)
        }
        .buttonStyle(.plain)
    }

    private func row(_ l: Lesson, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                if expanded.contains(l.id) { expanded.remove(l.id) } else { expanded.insert(l.id) }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    statusIcon(l).frame(width: 28)
                    Text("\(number)").font(theme.font(.cardTitle).monospacedDigit()).foregroundStyle(.secondary).frame(width: 22, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(MathPlain.render(l.title)).font(theme.font(.cardTitle))
                            if l.optional {
                                Text("Optional").font(.caption.bold()).padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.15), in: Capsule())
                            }
                        }
                        Text("\(l.parts.count) part\(l.parts.count == 1 ? "" : "s") · about \(minutes(l)) min")
                            .font(theme.font(.caption)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: expanded.contains(l.id) ? "chevron.up" : "chevron.down").foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("lessonRow")
            if expanded.contains(l.id) {
                VStack(alignment: .leading, spacing: 6) {
                    if !l.summary.isEmpty { Text(l.summary).font(.subheadline).foregroundStyle(.secondary) }
                    ForEach(Array(l.parts.enumerated()), id: \.offset) { i, p in
                        HStack(spacing: 10) {
                            Image(systemName: i < l.partsDone ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(i < l.partsDone ? .green : .secondary).font(.caption)
                            Text("\(i + 1)  \(MathPlain.render(p.title))").font(.subheadline)
                        }
                    }
                    Button(l.status == .notStarted ? "Start lesson" : l.status == .done ? "Take it again" : "Continue lesson") { open = l }
                        .buttonStyle(.borderedProminent).padding(.top, 4)
                }
                .padding(.leading, 74)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    @ViewBuilder private func statusIcon(_ l: Lesson) -> some View {
        switch l.status {
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.done)
        case .inProgress: Image(systemName: "circle.lefthalf.filled").foregroundStyle(theme.learn)
        case .notStarted: Image(systemName: "circle").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var skippedList: some View {
        let skipped = LessonPlanner.skipped(chapter)
        if !skipped.isEmpty {
            let titles = Dictionary(chapter.outline.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
            DisclosureGroup(isExpanded: $showSkipped) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("These parts of the chapter aren't taught in a lesson. Their exercises are still in practice.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(skipped, id: \.self) { s in
                        HStack(alignment: .firstTextBaseline) {
                            Text(MathPlain.render(titles[s.section_id] ?? "Section")).font(.subheadline.weight(.medium))
                            Text("— \(s.reason)").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 6)
            } label: {
                Text("Not in lessons (\(skipped.count))").font(.headline)
            }
            .padding(16)
            .card(theme)
        }
    }

    // MARK: Helpers

    private func continueLesson(_ lessons: [Lesson]) -> Lesson? {
        if let l = lessons.filter({ $0.status == .inProgress }).max(by: { ($0.lastOpened ?? .distantPast) < ($1.lastOpened ?? .distantPast) }) { return l }
        guard lessons.contains(where: { $0.status != .notStarted }) else { return nil }
        return lessons.first { $0.status == .notStarted && !$0.optional }
    }

    /// Rough time: about 5 minutes a part.
    private func minutes(_ l: Lesson) -> Int { max(5, l.parts.count * 5) }

    private func plan() {
        planning = true
        planError = nil
        Task {
            do { try await LessonPlanner.plan(chapter, context: context) } catch {
                if case ClaudeClient.ClientError.missingAPIKey? = error as? ClaudeClient.ClientError {
                    planError = "Lessons need a Claude API key. Add one in Settings."
                } else {
                    planError = "Couldn't plan the lessons (\(error.localizedDescription)). Try again."
                }
            }
            planning = false
        }
    }

    /// Practice limited to a lesson's sections.
    @MainActor
    static func practiceSet(_ lesson: Lesson) -> StudySet {
        guard let c = lesson.chapter else { return StudySet(title: lesson.title, chapters: [], questions: [], examMinutes: 30) }
        let nodes = c.outline
        let sections = lesson.allSectionIDs
        let byID = Dictionary(uniqueKeysWithValues: c.questions.map { ($0.id, $0) })
        let qs = c.activeQuestions.filter { q in
            let base = q.parentQuestionID.flatMap { byID[$0] } ?? q
            return sections.contains { StudySet.isWithin(base.sectionID, $0, nodes) }
        }
        return StudySet(title: lesson.title, chapters: [c], questions: qs, examMinutes: c.examMinutes)
    }
}
