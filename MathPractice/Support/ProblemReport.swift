import SwiftUI

/// Bundles everything needed to diagnose a problem (text, Claude's replies, images) into one .zip
/// that can be AirDropped to a Mac.
@MainActor
enum ProblemReport {
    enum Subject {
        case question(Question)
        case attempt(Attempt)
        case chapter(Chapter)

        var kind: String {
            switch self {
            case .question: return "question"
            case .attempt: return "grading"
            case .chapter: return "chapter"
            }
        }
    }

    static func build(_ subject: Subject, note: String) throws -> URL {
        let fm = FileManager.default
        let stamp = Self.stamp.string(from: Date())
        let name = "MathPractice-report-\(subject.kind)-\(stamp)"
        let dir = fm.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        var report: [String: Any] = [
            "report_type": subject.kind,
            "note": note,
            "created_at": ISO8601DateFormatter().string(from: Date()),
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
            "model": ClaudeClient.defaultModel,
        ]

        func write(_ data: Data?, _ file: String) {
            guard let data else { return }
            try? data.write(to: dir.appendingPathComponent(file))
        }

        switch subject {
        case let .question(q):
            report["question"] = questionInfo(q)
            write(q.figureData, "question_figure.jpg")
            write(sourcePage(q)?.imageData, "source_page.jpg")
            report["attempts"] = q.attempts.sorted { $0.startedAt < $1.startedAt }.map(attemptInfo)

        case let .attempt(a):
            report["attempt"] = attemptInfo(a)
            if let q = a.question {
                report["question"] = questionInfo(q)
                write(q.figureData, "question_figure.jpg")
                write(sourcePage(q)?.imageData, "source_page.jpg")
            }
            write(a.renderedImage, "her_work.png")

        case let .chapter(c):
            report["chapter"] = [
                "title": c.title, "status": c.statusRaw, "error": c.errorMessage ?? "",
                "progress_message": c.progressMessage, "exam_minutes": c.examMinutes,
                "page_count": c.pages.count,
                "answer_key_pages": c.sortedPages.filter(\.isAnswerKey).map { $0.order + 1 },
            ] as [String: Any]
            report["concepts"] = c.sortedConcepts.map {
                ["name": $0.name, "summary": $0.summary, "book_order": $0.bookOrder, "worked_example": $0.workedExample,
                 "question_count": $0.questions.count] as [String: Any]
            }
            report["questions"] = c.questions.sorted { ($0.pageIndex ?? 999, $0.createdAt) < ($1.pageIndex ?? 999, $1.createdAt) }
                .map(questionInfo)
            report["skills"] = c.skills.map {
                ["concept": $0.concept?.name ?? "", "difficulty": $0.difficulty, "mastery": $0.mastery,
                 "attempts": $0.attemptCount, "recent_results": $0.recentResults] as [String: Any]
            }
            for page in c.sortedPages {
                write(page.imageData, String(format: "page_%02d%@.jpg", page.order + 1, page.isAnswerKey ? "_answerkey" : ""))
            }
        }

        let json = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: dir.appendingPathComponent("report.json"))
        return try zip(dir, name: name)
    }

    private static func questionInfo(_ q: Question) -> [String: Any] {
        [
            "id": q.id.uuidString,
            "book_ref": q.bookRef,
            "source": q.sourceRaw,
            "status": q.statusRaw,
            "review_note": q.reviewNote ?? "",
            "concept": q.concept?.name ?? "",
            "difficulty": q.difficulty,
            "estimated_seconds": q.estimatedSeconds,
            "text": q.text,
            "has_figure": q.figureData != nil,
            "page": (q.pageIndex.map { $0 + 1 }) as Any,
            "reference_answer": q.referenceAnswer,
            "reference_solution": q.referenceSolution,
            "answer_key_answer": q.answerKeyAnswer ?? "",
            "parent_edited": q.parentEdited,
            "generated_from": q.parentQuestionID?.uuidString ?? "",
        ]
    }

    private static func attemptInfo(_ a: Attempt) -> [String: Any] {
        [
            "id": a.id.uuidString,
            "mode": a.modeRaw,
            "started_at": ISO8601DateFormatter().string(from: a.startedAt),
            "active_seconds": a.activeSeconds,
            "verdict": a.verdictRaw,
            "corrected_to": a.correctionRaw ?? "",
            "mistake_type": a.mistakeTypeRaw ?? "",
            "transcribed_answer": a.transcribedAnswer,
            "error_step": a.errorStep,
            "feedback": a.feedback,
            "confidence": a.graderConfidence,
            "grader_log": a.graderLog,
        ]
    }

    private static func sourcePage(_ q: Question) -> PageImage? {
        guard let index = q.pageIndex else { return nil }
        return q.chapter?.sortedPages.first { $0.order == index }
    }

    /// Uses the system's "prepare for upload" coordination, which produces a .zip of a directory.
    private static func zip(_ dir: URL, name: String) throws -> URL {
        let fm = FileManager.default
        let dest = fm.temporaryDirectory.appendingPathComponent("\(name).zip")
        try? fm.removeItem(at: dest)
        var coordError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: dir, options: .forUploading, error: &coordError) { zipped in
            do { try fm.copyItem(at: zipped, to: dest) } catch { copyError = error }
        }
        if let e = coordError ?? (copyError as NSError?) { throw e }
        try? fm.removeItem(at: dir)
        return dest
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()
}

/// "Report a problem" button → describe it → share the .zip (AirDrop to the Mac).
struct ReportProblemButton: View {
    let subject: ProblemReport.Subject
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: { Label("Report a problem", systemImage: "exclamationmark.bubble") }
            .sheet(isPresented: $showing) { ReportProblemSheet(subject: subject) }
    }
}

private struct ReportProblemSheet: View {
    let subject: ProblemReport.Subject
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var fileURL: URL?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(placeholder, text: $note, axis: .vertical).lineLimit(4...10)
                } header: {
                    Text("What went wrong?")
                } footer: {
                    Text(footer)
                }
                Section {
                    if let fileURL {
                        ShareLink(item: fileURL) { Label("Send report (AirDrop to your Mac)", systemImage: "square.and.arrow.up") }
                        Text(fileURL.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("Create report") { create() }
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Report a problem")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onChange(of: note) { _, _ in fileURL = nil }
        }
    }

    private var placeholder: String {
        switch subject {
        case .question: return "e.g. The question text is wrong / the answer is wrong / the figure is cut off"
        case .attempt: return "e.g. My answer 1/2 is right but it was marked wrong"
        case .chapter: return "e.g. Questions 12–15 on page 3 are missing / concepts are mixed up"
        }
    }

    private var footer: String {
        switch subject {
        case .question: return "Includes the question, its answer and solution, the figure, the original page and your answers to it."
        case .attempt: return "Includes the question, your handwritten work, Claude's full grading reply and the original page."
        case .chapter: return "Includes every scanned page, all extracted questions and answers, the concepts and your progress."
        }
    }

    private func create() {
        do { fileURL = try ProblemReport.build(subject, note: note); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
