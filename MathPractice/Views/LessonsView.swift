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
        let current = currentLesson(lessons)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if lessons.isEmpty {
                    prepareCard
                } else {
                    overview(lessons)
                    VStack(spacing: 0) {
                        ForEach(Array(lessons.enumerated()), id: \.element.id) { i, l in
                            pathStep(l, number: lessons.first?.optional == true ? i : i + 1,   // a warm-up lesson is number 0
                                     isCurrent: l.id == current?.id, isLast: i == lessons.count - 1)
                        }
                    }
                    skippedList
                }
            }
            .padding(24)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .themedBackground(theme)
        .navigationTitle("Lessons")
        .toolbar {
            if !lessons.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { plan() } label: { Label("Plan the lessons again", systemImage: "arrow.clockwise") }
                            .disabled(planning)
                    } label: { Label("More", systemImage: "ellipsis.circle") }
                }
            }
        }
        .fullScreenCover(item: $open) { l in LessonPage(lesson: l, onNext: { next in open = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { open = next } }) }
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-openLesson"), open == nil { open = lessons.first }
        }
        #endif
    }

    // MARK: Pieces

    private var prepareCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "graduationcap.fill").font(.system(size: 30)).foregroundStyle(.white)
                .frame(width: 60, height: 60).background(theme.learn, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text("Learn this chapter, one lesson at a time").font(theme.font(.section))
            Text("A tutor walks you through each part of the chapter out loud, with the book's examples, then gives you one to try. Ask a question any time.")
                .font(theme.font(.body)).foregroundStyle(.secondary)
            if planning {
                HStack(spacing: 10) { ProgressView(); Text("Planning the lessons… (about a minute)").foregroundStyle(.secondary) }
            } else {
                Button { plan() } label: { Label("Prepare lessons", systemImage: "sparkles").padding(.horizontal, 6) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
            if let planError { Text(planError).font(theme.font(.label)).foregroundStyle(theme.notQuite) }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(theme)
    }

    /// How far she is through the chapter's lessons.
    private func overview(_ lessons: [Lesson]) -> some View {
        let done = lessons.filter { $0.status == .done }.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(done) of \(lessons.count) lessons done").font(theme.font(.section))
                Spacer()
                let parts = lessons.map(\.parts.count).reduce(0, +)
                Text("\(parts) parts · about \(lessons.map(minutes).reduce(0, +)) min in all")
                    .font(theme.font(.label)).foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                ForEach(lessons) { l in
                    Capsule().fill(l.status == .done ? theme.done : l.status == .inProgress ? theme.learn : Color.secondary.opacity(0.18))
                        .frame(height: 8)
                }
            }
            Text("Each lesson teaches one part of the book. Ask a question any time — just start talking.")
                .font(theme.font(.label)).foregroundStyle(.secondary)
        }
        .padding(20)
        .card(theme)
    }

    /// One lesson on the path: a badge on the line, and a card.
    private func pathStep(_ l: Lesson, number: Int, isCurrent: Bool, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                badge(l, number: number)
                if !isLast {
                    Rectangle().fill(l.status == .done ? theme.done.opacity(0.5) : Color.secondary.opacity(0.2))
                        .frame(width: 3).frame(maxHeight: .infinity)
                }
            }
            .frame(width: 44)
            lessonCard(l, isCurrent: isCurrent)
                .padding(.bottom, isLast ? 0 : 14)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func badge(_ l: Lesson, number: Int) -> some View {
        ZStack {
            switch l.status {
            case .done:
                Circle().fill(theme.done)
                Image(systemName: "checkmark").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
            case .inProgress:
                Circle().fill(theme.surface)
                Circle().stroke(theme.learn.opacity(0.2), lineWidth: 4)
                Circle().trim(from: 0, to: max(0.08, Double(l.partsDone) / Double(max(1, l.parts.count))))
                    .stroke(theme.learn, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                Text("\(number)").font(.system(size: 17, weight: .bold).monospacedDigit()).foregroundStyle(theme.learn)
            case .notStarted:
                Circle().fill(theme.surface)
                Circle().strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: l.optional ? [4, 3] : []))
                Text("\(number)").font(.system(size: 17, weight: .semibold).monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }

    private func lessonCard(_ l: Lesson, isCurrent: Bool) -> some View {
        let isOpen = expanded.contains(l.id)
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy) { if isOpen { expanded.remove(l.id) } else { expanded.insert(l.id) } }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            if isCurrent { tag(l.status == .inProgress ? "In progress" : "Up next", theme.learn) }
                            if l.optional { tag("Optional", .secondary) }
                            if l.status == .done { tag("Done", theme.done) }
                        }
                        Text(MathPlain.render(l.title)).font(theme.font(.cardTitle)).foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        if !l.summary.isEmpty {
                            Text(l.summary).font(theme.font(.label)).fontWeight(.regular).foregroundStyle(.secondary)
                                .lineLimit(isOpen ? nil : 2).multilineTextAlignment(.leading)
                        }
                        Label(l.status == .inProgress ? "Part \(min(l.partsDone + 1, l.parts.count)) of \(l.parts.count)"
                              : "\(l.parts.count) part\(l.parts.count == 1 ? "" : "s") · about \(minutes(l)) min",
                              systemImage: "clock")
                            .font(theme.font(.caption)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("lessonRow")
            if isOpen {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(l.parts.enumerated()), id: \.offset) { i, p in
                        HStack(spacing: 12) {
                            Image(systemName: i < l.partsDone ? "checkmark.circle.fill" : i == l.partsDone && l.status == .inProgress ? "circle.inset.filled" : "circle")
                                .foregroundStyle(i < l.partsDone ? theme.done : i == l.partsDone && l.status == .inProgress ? theme.learn : Color.secondary.opacity(0.5))
                            Text("Part \(i + 1)").font(theme.font(.caption)).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                            Text(MathPlain.render(p.title)).font(theme.font(.body))
                        }
                        .padding(.vertical, 7)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            if isCurrent || isOpen {
                Button { open = l } label: {
                    Label(l.status == .notStarted ? "Start lesson" : l.status == .done ? "Take it again" : "Continue lesson",
                          systemImage: l.status == .done ? "arrow.counterclockwise" : "play.fill")
                        .font(theme.font(.label).weight(.semibold))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(l.status == .done ? .secondary : theme.learn)
                .controlSize(.large)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(theme)
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: theme.radius, style: .continuous).stroke(theme.learn.opacity(0.55), lineWidth: 2)
            }
        }
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .bold)).kerning(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    @ViewBuilder private var skippedList: some View {
        let skipped = LessonPlanner.skipped(chapter)
        if !skipped.isEmpty {
            let titles = Dictionary(chapter.outline.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
            DisclosureGroup(isExpanded: $showSkipped) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(skipped, id: \.self) { s in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(MathPlain.render(titles[s.section_id] ?? "Section")).font(theme.font(.body).weight(.medium))
                            Text(s.reason).font(theme.font(.label)).fontWeight(.regular).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "tray.full.fill").foregroundStyle(.secondary)
                        .frame(width: 40, height: 40).background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Not in lessons (\(skipped.count))").font(theme.font(.cardTitle)).foregroundStyle(.primary)
                        Text("Extra reading and reviews. Their exercises are still in practice.")
                            .font(theme.font(.caption)).foregroundStyle(.secondary)
                    }
                }
            }
            .tint(.secondary)
            .padding(18)
            .card(theme)
            .padding(.leading, 60)
        }
    }

    // MARK: Helpers

    /// The lesson to do next: the one in progress, else the first not started (core before optional).
    private func currentLesson(_ lessons: [Lesson]) -> Lesson? {
        if let l = lessons.filter({ $0.status == .inProgress }).max(by: { ($0.lastOpened ?? .distantPast) < ($1.lastOpened ?? .distantPast) }) { return l }
        return lessons.first { $0.status == .notStarted && !$0.optional } ?? lessons.first { $0.status == .notStarted }
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
