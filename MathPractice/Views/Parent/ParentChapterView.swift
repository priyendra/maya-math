import SwiftUI
import SwiftData

struct ParentChapterView: View {
    @Bindable var chapter: Chapter
    @Environment(\.modelContext) private var context

    private var questionsToCheck: [Question] {
        chapter.questions.filter { $0.status == .needsParentReview }.sorted { $0.createdAt < $1.createdAt }
    }
    private var gradingsToCheck: [Attempt] {
        chapter.allAttempts.filter { $0.isGraded && $0.effectiveVerdict == .needsReview }.sorted { $0.startedAt > $1.startedAt }
    }
    private var recentAttempts: [Attempt] {
        Array(chapter.allAttempts.filter(\.isGraded).sorted { $0.startedAt > $1.startedAt }.prefix(30))
    }

    var body: some View {
        List {
            Section("Chapter") {
                TextField("Title", text: $chapter.title)
                Stepper("Exam length: \(chapter.examMinutes) min", value: $chapter.examMinutes, in: 5...120, step: 5)
                NavigationLink("Progress report") { ProgressReportView(chapter: chapter) }
                ReportProblemButton(subject: .chapter(chapter))
            }

            if !questionsToCheck.isEmpty {
                Section {
                    ForEach(questionsToCheck) { q in
                        NavigationLink { QuestionEditView(question: q) } label: { questionRow(q, showNote: true) }
                    }
                } header: {
                    Text("Questions to check (\(questionsToCheck.count))")
                } footer: {
                    Text("Claude wasn't sure of the answer to these. They're held back from practice until you approve or fix them.")
                }
            }

            if !gradingsToCheck.isEmpty {
                Section("Gradings to check (\(gradingsToCheck.count))") {
                    ForEach(gradingsToCheck) { a in
                        NavigationLink { AttemptReviewView(attempt: a) } label: { attemptRow(a) }
                    }
                }
            }

            ForEach(chapter.sortedConcepts) { concept in
                Section(concept.name) {
                    ForEach(concept.questions.filter { $0.status != .needsParentReview }
                        .sorted { ($0.difficulty, $0.createdAt) < ($1.difficulty, $1.createdAt) }) { q in
                        NavigationLink { QuestionEditView(question: q) } label: { questionRow(q, showNote: false) }
                    }
                }
            }

            if !recentAttempts.isEmpty {
                Section("Recent answers") {
                    ForEach(recentAttempts) { a in
                        NavigationLink { AttemptReviewView(attempt: a) } label: { attemptRow(a) }
                    }
                }
            }
        }
        .navigationTitle(chapter.title)
        .onDisappear { try? context.save() }
    }

    private func questionRow(_ q: Question, showNote: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(q.bookRef.isEmpty ? (q.source == .generated ? "Generated" : "Question") : q.bookRef).font(.caption.bold())
                Text(String(repeating: "●", count: q.difficulty)).font(.caption2).foregroundStyle(.orange)
                if q.figureData != nil { Image(systemName: "photo").font(.caption) }
                if q.status == .retired { Text("Removed").font(.caption).foregroundStyle(.red) }
            }
            Text(MathText.plainPreview(q.text)).lineLimit(2)
            Text("Answer: \(MathText.plainPreview(q.referenceAnswer))").font(.caption).foregroundStyle(.secondary)
            if showNote, let note = q.reviewNote { Text(note).font(.caption).foregroundStyle(.orange).lineLimit(3) }
        }
    }

    private func attemptRow(_ a: Attempt) -> some View {
        HStack {
            VerdictBadge(verdict: a.effectiveVerdict)
            VStack(alignment: .leading) {
                Text(MathText.plainPreview(a.question?.text ?? "")).lineLimit(1)
                Text(a.startedAt.formatted(date: .abbreviated, time: .shortened) + " · \(Int(a.activeSeconds))s"
                     + (a.mistakeType.map { " · \($0.displayName)" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct VerdictBadge: View {
    let verdict: Verdict
    var body: some View {
        switch verdict {
        case .correct: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .incorrect: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .needsReview: Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange)
        }
    }
}

struct QuestionEditView: View {
    @Bindable var question: Question
    @Environment(\.modelContext) private var context
    @State private var showPage = false
    @State private var resolving = false
    @State private var error: String?

    var body: some View {
        Form {
            if let note = question.reviewNote, question.status == .needsParentReview {
                Section("Why this needs a check") { Text(note).foregroundStyle(.orange) }
            }
            Section("Question") {
                MathText(markdown: question.text, fontSize: 18)
                TextField("Question text (Markdown + $LaTeX$)", text: $question.text, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                if let fig = question.figureData, let image = UIImage(data: fig) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 260)
                }
                if question.pageIndex != nil {
                    Button("Show original page") { showPage = true }
                }
            }
            Section("Answer") {
                MathText(markdown: question.referenceAnswer, fontSize: 18)
                TextField("Final answer", text: $question.referenceAnswer, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                if let key = question.answerKeyAnswer { LabeledContent("Book answer key", value: key) }
            }
            Section("Solution") {
                MathText(markdown: question.referenceSolution, fontSize: 16)
                TextField("Solution", text: $question.referenceSolution, axis: .vertical)
                    .font(.system(.footnote, design: .monospaced))
                Button(resolving ? "Solving…" : "Ask Claude to solve again") { resolve() }.disabled(resolving)
                if let error { Text(error).foregroundStyle(.red) }
            }
            Section("Category") {
                if let chapter = question.chapter {
                    Picker("Concept", selection: $question.concept) {
                        ForEach(chapter.sortedConcepts) { Text($0.name).tag(Optional($0)) }
                    }
                }
                Picker("Difficulty", selection: $question.difficulty) {
                    Text("1 · Basic").tag(1); Text("2 · Medium").tag(2); Text("3 · Hard").tag(3)
                }
                Stepper("Expected time: \(question.estimatedSeconds)s", value: $question.estimatedSeconds, in: 20...1200, step: 15)
            }
            Section {
                if question.status != .ok {
                    Button("Approve — use for practice") { setStatus(.ok) }
                }
                if question.status != .retired {
                    Button("Remove from practice", role: .destructive) { setStatus(.retired) }
                }
            }
            Section { ReportProblemButton(subject: .question(question)) }
        }
        .navigationTitle(question.bookRef.isEmpty ? "Question" : question.bookRef)
        .onChange(of: question.text) { _, _ in question.parentEdited = true }
        .onChange(of: question.referenceAnswer) { _, _ in question.parentEdited = true }
        .onChange(of: question.difficulty) { _, _ in ensureSkill() }
        .onChange(of: question.concept) { _, _ in ensureSkill() }
        .onDisappear { try? context.save() }
        .sheet(isPresented: $showPage) {
            if let chapter = question.chapter, let index = question.pageIndex,
               let page = chapter.sortedPages.first(where: { $0.order == index }), let image = UIImage(data: page.imageData) {
                ScrollView { Image(uiImage: image).resizable().scaledToFit() }
            }
        }
    }

    private func setStatus(_ status: QuestionStatus) {
        question.status = status
        if status == .ok { question.reviewNote = nil }
        ensureSkill()
        try? context.save()
    }

    private func ensureSkill() {
        if let chapter = question.chapter { ChapterProcessor.shared.ensureSkills(chapter, context: context) }
    }

    private func resolve() {
        resolving = true
        error = nil
        let ctx = QuestionContext(text: question.text, figureJPEG: question.figureData, conceptName: question.concept?.name ?? "")
        let key = question.answerKeyAnswer
        Task {
            do {
                let s = try await ClaudeServices.live.solveVerified(ctx, answerKey: key)
                question.referenceSolution = s.solution
                question.referenceAnswer = s.finalAnswer
                question.reviewNote = s.note
                if s.trusted && question.status == .needsParentReview { question.status = .ok }
                try? context.save()
            } catch {
                self.error = error.localizedDescription
            }
            resolving = false
        }
    }
}
