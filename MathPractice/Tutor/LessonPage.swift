import SwiftUI
import PencilKit

/// A lesson in two halves: the book on top (untouched, the block being taught highlighted) and the teacher's board
/// below, where the teacher works the examples, asks quick fill-in-the-blank questions, and gives "your turn"
/// problems. She can write on both halves and ask at any time.
struct LessonPage: View {
    let lesson: Lesson
    var onNext: ((Lesson) -> Void)? = nil
    /// The lessons "Next lesson" walks through (e.g. the lessons of the section she asked to be taught).
    var queue: [Lesson]? = nil
    @StateObject private var tutor: LessonSession
    @StateObject private var ink = PageInk()
    @StateObject private var book = BookInk()
    @State private var practicing = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.theme) private var theme

    init(lesson: Lesson, queue: [Lesson]? = nil, onNext: ((Lesson) -> Void)? = nil) {
        self.lesson = lesson
        self.queue = queue
        self.onNext = onNext
        _tutor = StateObject(wrappedValue: LessonSession(lesson: lesson))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { g in
                VStack(spacing: 0) {
                    Group {
                        if let chapter = lesson.chapter, let section = tutor.bookSection {
                            BookPane(chapter: chapter, section: section, pointAt: tutor.bookPointer, ink: book)
                        } else {
                            Color(uiColor: .systemBackground)
                        }
                    }
                    .frame(height: g.size.height / 2)
                    Divider()
                    InkPageView(ink: ink)
                        .background(Color(uiColor: .systemBackground))
                        .overlay(alignment: .topLeading) { blankButtons }
                        .clipped()
                }
            }
                .safeAreaInset(edge: .bottom) { bottomBar }
                .navigationTitle(MathPlain.render(lesson.title))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { tutor.end(); dismiss() }
                    }
                    ToolbarItem(placement: .principal) { progress }
                }
        }
        .onAppear {
            ink.install(LessonContent(tutor: tutor, ink: ink).environment(\.theme, theme).fontDesign(theme.design))
            ink.onInk = { [weak tutor, weak ink] in
                tutor?.inkChanged()
                if let id = tutor?.activeBlank { tutor?.blankHasInk = ink?.image(in: id) != nil }
            }
            ink.onTap = { [weak tutor] in tutor?.interrupt() }
            book.onTap = { [weak tutor] in tutor?.interrupt() }
            tutor.snapshot = { [weak ink, weak book] in LessonPage.snapshot(book: book?.snapshot(), board: ink?.snapshot()) }
            tutor.workBelow = { [weak ink] id in ink?.work(below: id) }
            tutor.inkIn = { [weak ink] id in ink?.image(in: id) }
            tutor.start()
        }
        .onChange(of: tutor.pointer) { _, id in ink.reveal(id) }
        .onChange(of: tutor.revealRequest) { _, id in
            // After the cursor has moved to the problem: show the writing space under it too.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { ink.reveal(id) }
        }
        .onChange(of: tutor.elements.count) { _, _ in
            // New content: bring the newest thing into view (the cursor usually follows).
            if tutor.pointer == nil, let last = tutor.elements.last { ink.reveal(last.id) }
        }
        .onChange(of: ink.tool) { _, t in book.setTool(t) }
        .onChange(of: scenePhase) { _, p in if p == .background { tutor.end() } }
        .onDisappear { tutor.end() }
        .fullScreenCover(isPresented: $practicing) { PracticeSessionView(set: LessonsView.practiceSet(lesson)) }
    }

    private var progress: some View {
        VStack(spacing: 2) {
            Text(MathPlain.render(lesson.title)).font(.headline).lineLimit(1)
            let n = tutor.parts.count
            if n > 0 {
                HStack(spacing: 4) {
                    Text(tutor.phase == .done ? "All \(n) parts done" : "Part \(min(tutor.currentPart + 1, n)) of \(n)")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(0..<n, id: \.self) { i in
                        Circle().fill(i < lesson.partsDone ? theme.done : i == tutor.currentPart ? theme.learn : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }
            }
        }
    }

    // MARK: Bottom bar

    /// Two pieces: her pen tools, and the tutor (what it's doing + what she can do next).
    private var bottomBar: some View {
        HStack(alignment: .bottom, spacing: 12) {
            HStack(spacing: 4) {
                toolButton(.pen, "pencil.tip", "Pencil")
                toolButton(.highlighter, "highlighter", "Highlighter")
                toolButton(.eraser, "eraser", "Eraser")
                Divider().frame(height: 26).padding(.horizontal, 4)
                Button { ink.undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 36, height: 36) }
                    .accessibilityLabel("Undo")
                Button { ink.clear(); book.clear() } label: { Image(systemName: "trash").frame(width: 36, height: 36) }
                    .accessibilityLabel("Clear my writing").disabled(!ink.hasInk)
            }
            .padding(6)
            .background(.regularMaterial, in: Capsule())
            HStack(spacing: 12) {
                status.frame(maxWidth: .infinity, alignment: .leading)
                controls
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(minHeight: 56)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: min(theme.radius + 6, 28), style: .continuous))
        }
        .font(theme.font(.body))
        .padding(.horizontal, 16).padding(.bottom, 8)
    }

    private func toolButton(_ t: PageInk.Tool, _ icon: String, _ label: String) -> some View {
        Button { ink.tool = t } label: {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                .frame(width: 36, height: 36)
                .foregroundStyle(ink.tool == t ? Color.white : Color.primary)
                .background(ink.tool == t ? AnyShapeStyle(theme.accent) : AnyShapeStyle(Color.clear), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(ink.tool == t ? .isSelected : [])
    }

    @ViewBuilder private var status: some View {
        HStack(spacing: 10) {
            if case .preparing = tutor.phase {
                ProgressView()
                Text("Getting part \(tutor.currentPart + 1) ready…").foregroundStyle(.secondary)
            } else {
                switch tutor.state {
                case .off:
                    if tutor.phase == .done { Label("Lesson done", systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
                case .starting:
                    ProgressView()
                    Text("Getting ready…").foregroundStyle(.secondary)
                case .thinking:
                    ProgressView()
                    Text("Thinking…").foregroundStyle(.secondary)
                case .speaking:
                    Image(systemName: "speaker.wave.2.fill").foregroundStyle(.blue).symbolEffect(.variableColor.iterative)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(MathPlain.render(tutor.caption)).lineLimit(2)
                        Text("Tap the page to ask a question").font(.caption).foregroundStyle(.secondary)
                    }
                case .listening:
                    Image(systemName: "mic.fill").foregroundStyle(.green).symbolEffect(.pulse)
                    Text(tutor.heard.isEmpty ? (tutor.phase == .questions ? "Any questions? Ask, or say \u{201C}go on\u{201D}" : "Listening… ask anything, and circle what you mean") : tutor.heard)
                        .lineLimit(2).foregroundStyle(tutor.heard.isEmpty ? .secondary : .primary)
                        .accessibilityIdentifier("tutorListening")
                case let .waiting(message):
                    Image(systemName: tutor.phase == .yourTurn ? "pencil" : "info.circle").foregroundStyle(.secondary)
                    Text(message).font(.callout).lineLimit(3).accessibilityIdentifier("lessonMessage")
                }
            }
        }
    }

    @ViewBuilder private var controls: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-fakeTutor"), tutor.state == .listening {
            Button("Say") { tutor.debugSay("Why is it seven x?") }.accessibilityIdentifier("debugSay")
        }
        #endif
        switch tutor.phase {
        case .failed:
            Button { tutor.retry() } label: { Label("Try again", systemImage: "arrow.clockwise") }.buttonStyle(.borderedProminent)
        case .done:
            Button("Practice this lesson") { practicing = true }.buttonStyle(.bordered)
            if let next = nextLesson, let onNext {
                Button { tutor.end(); onNext(next) } label: { Label("Next lesson", systemImage: "arrow.right") }
                    .buttonStyle(.borderedProminent)
            }
        case .yourTurn:
            Button { tutor.ask() } label: { Label("Ask", systemImage: "mic.fill") }.buttonStyle(.bordered)
            Button { tutor.check() } label: { Label("Check", systemImage: "checkmark") }
                .buttonStyle(.borderedProminent).accessibilityIdentifier("lessonCheck")
        case .narrating, .questions, .reviewing:
            if tutor.state == .speaking || tutor.state == .thinking {
                Button { tutor.ask() } label: { Label("Pause", systemImage: "pause.fill") }.buttonStyle(.bordered)
            } else if tutor.state != .listening {
                Button { tutor.ask() } label: { Label("Ask", systemImage: "mic.fill") }.buttonStyle(.bordered)
            }
            if tutor.state == .listening || (tutor.state.isWaiting && tutor.activeBlank == nil) || tutor.phase == .questions {
                Button { tutor.goOn() } label: { Label("Go on", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("lessonGoOn")
            }
        case .preparing, .checking:
            EmptyView()
        }
    }

    // MARK: Blank buttons

    /// ✓ (check) and ? (not sure) beside the blank she is filling in. Real buttons over the page, so neither the
    /// Pencil nor a finger leaves a mark on them.
    @ViewBuilder private var blankButtons: some View {
        if let id = tutor.activeBlank, let f = ink.frames[id + "_end"] {
            HStack(spacing: 10) {
                Button { tutor.checkBlank() } label: {
                    Group {
                        if tutor.checkingBlank { ProgressView().tint(.white) }
                        else { Image(systemName: "checkmark").font(.system(size: 18, weight: .bold)) }
                    }
                    .frame(width: 44, height: 44).foregroundStyle(.white)
                    .background(theme.learn.opacity(tutor.blankHasInk ? 1 : 0.35), in: Circle())
                }
                .accessibilityLabel("Check")
                .accessibilityIdentifier("blankCheck")
                Button { tutor.showBlank() } label: {
                    Image(systemName: "questionmark").font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44).foregroundStyle(theme.learn)
                        .background(theme.learn.opacity(0.12), in: Circle())
                }
                .accessibilityLabel("Not sure")
                .accessibilityIdentifier("blankNotSure")
            }
            .position(x: f.minX + 54, y: f.midY - ink.offset.y)
        }
    }

    /// What she's looking at, for her questions: the book half above the board half.
    static func snapshot(book: UIImage?, board: PageSnapshot?) -> PageSnapshot? {
        guard let book else { return board }
        let boardImage = board.flatMap { UIImage(data: $0.jpeg) }
        let width = max(book.size.width, boardImage?.size.width ?? 0)
        let size = CGSize(width: width, height: book.size.height + (boardImage?.size.height ?? 0))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            book.draw(at: .zero)
            boardImage?.draw(at: CGPoint(x: 0, y: book.size.height))
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.75) else { return board }
        return PageSnapshot(jpeg: jpeg, visibleParts: ["the book (top half)"] + (board?.visibleParts ?? []),
                            newMarks: board?.newMarks ?? false)
    }

    private var nextLesson: Lesson? {
        if let queue, let i = queue.firstIndex(where: { $0.id == lesson.id }) { return queue.dropFirst(i + 1).first }
        guard let all = lesson.chapter?.sortedLessons, let i = all.firstIndex(where: { $0.id == lesson.id }) else { return nil }
        return all.dropFirst(i + 1).first
    }
}

extension VoiceTutor.State {
    var isWaiting: Bool { if case .waiting = self { return true } else { return false } }
}

// MARK: - Page content (rendered under the ink)

private struct LessonContent: View {
    @ObservedObject var tutor: LessonSession
    let ink: PageInk
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(tutor.elements) { e in element(e) }
            // Her space: a faint ruled area below the lesson.
            VStack(alignment: .leading, spacing: 0) {
                Label("Your space to write", systemImage: "pencil.tip").font(theme.font(.caption)).foregroundStyle(.tertiary)
                    .padding(.bottom, 14)
                ForEach(0..<8, id: \.self) { _ in
                    Rectangle().fill(Color.secondary.opacity(0.10)).frame(height: 1).padding(.top, 48)
                }
            }
            .padding(.top, 8)
        }
        .padding(28)
        .frame(maxWidth: 820, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .coordinateSpace(name: "page")
        .overlayPreferenceValue(PartFrames.self) { frames in
            PointerOverlay(target: tutor.pointer.flatMap { frames[$0] })
        }
        .background(GeometryReader { g in Color.clear.preference(key: ContentHeight.self, value: g.size.height) })
        .onPreferenceChange(PartFrames.self) { ink.setFrames($0) }
        .onPreferenceChange(ContentHeight.self) { ink.setContentHeight($0) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private func element(_ e: LessonSession.Element) -> some View {
        switch e {
        case let .header(part, title, earlier):
            if earlier {
                Label("Part \(part + 1) · \(MathPlain.render(title))", systemImage: "checkmark.circle.fill")
                    .font(theme.font(.label)).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.08), in: Capsule())
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    if part > 0 { Divider().padding(.bottom, 18) }
                    Text("PART \(part + 1) OF \(tutor.lesson.parts.count)").font(theme.font(.caption).weight(.bold)).kerning(1)
                        .foregroundStyle(theme.learn)
                    Text(MathPlain.render(title)).font(theme.font(.pageTitle))
                }
                .padding(.top, part == 0 ? 0 : 10)
                .part(e.id)
            }
        case let .item(item):
            itemView(item).part(item.id)
        case let .board(b):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "pencil.line").foregroundStyle(theme.board)
                MathText(markdown: b.markdown, fontSize: 21)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(theme.board.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .leading) { Capsule().fill(theme.board.opacity(0.6)).frame(width: 3).padding(.vertical, 8) }
            .part(b.id)
        case let .turn(id, qid):
            if let q = tutor.questionsByID[qid] {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "pencil.and.outline").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 32, height: 32).background(theme.done, in: Circle())
                        Text("Your turn").font(theme.font(.cardTitle))
                        Spacer()
                        if !q.printedNumber.isEmpty { Text("Book #\(q.printedNumber)").font(theme.font(.caption)).foregroundStyle(.secondary) }
                        if let a = tutor.answers[id] { verdict(a) }
                    }
                    QuestionPanel(question: q)
                    Text("Work it out below, then tap Check.").font(theme.font(.caption)).foregroundStyle(.secondary)
                }
                .padding(18)
                .background(theme.done.opacity(0.06), in: RoundedRectangle(cornerRadius: theme.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: theme.radius, style: .continuous).stroke(theme.done.opacity(0.45), lineWidth: 1.5))
                .part(id)
                Color.clear.frame(height: 260).part(id + "_room")   // room for her answer
            }
        case let .blank(id, line, answer):
            blankLine(id: id, line: line, answer: answer)
        case .finished:
            HStack(alignment: .center, spacing: 18) {
                Image(systemName: "star.fill").font(.system(size: 30)).foregroundStyle(.white)
                    .frame(width: 64, height: 64).background(theme.done.gradient, in: Circle())
                VStack(alignment: .leading, spacing: 8) {
                    Text("Lesson done!").font(theme.font(.section))
                    Text("You finished all \(tutor.lesson.parts.count) part\(tutor.lesson.parts.count == 1 ? "" : "s") of \(MathPlain.render(tutor.lesson.title)).")
                        .font(theme.font(.body)).foregroundStyle(.secondary)
                    let results = tutor.answers.values.sorted { $0.startedAt < $1.startedAt }
                    if !results.isEmpty {
                        HStack(spacing: 6) {
                            Text("Your turns").font(theme.font(.caption)).foregroundStyle(.secondary)
                            ForEach(results, id: \.id) { a in
                                let v = a.effectiveVerdict
                                Image(systemName: v == .correct ? "checkmark" : v == .incorrect ? "arrow.uturn.left" : "questionmark")
                                    .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(v == .correct ? theme.done : v == .incorrect ? theme.notQuite : theme.attention, in: Circle())
                            }
                        }
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.done.opacity(0.07), in: RoundedRectangle(cornerRadius: theme.radius, style: .continuous))
            .part(e.id)
        }
    }

    /// A board line with a blank: the math before it, the blank (she writes in it), the math after it.
    @ViewBuilder private func blankLine(id: String, line: String, answer: String) -> some View {
        let pieces = line.components(separatedBy: "___")
        let before = pieces[0].trimmingCharacters(in: .whitespaces)
        let after = pieces.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let outcome = tutor.blankResults[id]
        let answerMD = answer.contains("$") || answer.contains(" ") || answer.count > 12 ? answer : "$\(answer)$"
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "pencil.line").foregroundStyle(theme.board)
            if !before.isEmpty { MathText(markdown: before, fontSize: 21).frame(width: Self.mathWidth(before)) }
            ZStack {
                if outcome == .shown { MathText(markdown: answerMD, fontSize: 21).frame(width: 110).foregroundStyle(theme.board) }
            }
            .frame(width: 130, height: 60)
            .background(outcome == nil ? theme.learn.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(outcome == nil ? theme.learn : theme.board.opacity(0.25), style: StrokeStyle(lineWidth: outcome == nil ? 2 : 1, dash: [6, 5])))
            .part(id)
            if !after.isEmpty { MathText(markdown: after, fontSize: 21).frame(width: Self.mathWidth(after)) }
            switch outcome {
            case .right?:
                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(theme.done)
            case .wrong?:
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right").foregroundStyle(theme.notQuite)
                    MathText(markdown: answerMD, fontSize: 21).frame(width: Self.mathWidth(answerMD))
                }
            default:
                Color.clear.frame(width: 110, height: 44).part(id + "_end")   // room for ✓ and ?
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(theme.board.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .leading) { Capsule().fill(theme.board.opacity(0.6)).frame(width: 3).padding(.vertical, 8) }
        .part(id + "_line")
    }

    /// About how wide a short piece of math is when typeset (MathText takes the width it is given).
    static func mathWidth(_ md: String) -> CGFloat {
        let plain = MathPlain.render(md) as NSString
        let w = plain.size(withAttributes: [.font: UIFont.systemFont(ofSize: 21)]).width
        return min(520, w * 1.25 + 14)
    }

    @ViewBuilder private func itemView(_ item: LessonPartScript.Item) -> some View {
        switch item.kind {
        case "heading":
            MathText(markdown: "**\(item.markdown)**", fontSize: 22)
                .padding(.top, 6)
        case "example":
            MathText(markdown: item.markdown, fontSize: 21)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.attention.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .leading) { Capsule().fill(theme.attention).frame(width: 3).padding(.vertical, 8) }
        case "figure":
            VStack(alignment: .leading, spacing: 4) {
                if let id = item.blockID, let data = tutor.lesson.chapter?.blocks.first(where: { $0.id == id })?.imageData,
                   let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().scaledToFit().frame(maxWidth: 560, maxHeight: 360, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                if !item.markdown.isEmpty { MathText(markdown: item.markdown, fontSize: 16).opacity(0.75) }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        default:
            MathText(markdown: item.markdown, fontSize: 20)
        }
    }

    @ViewBuilder private func verdict(_ a: Attempt) -> some View {
        if !a.isGraded {
            ProgressView()
        } else {
            switch a.effectiveVerdict {
            case .correct: Label("Right", systemImage: "checkmark.circle.fill").foregroundStyle(theme.done).font(theme.font(.label))
            case .incorrect: Label("Not quite", systemImage: "arrow.uturn.left.circle.fill").foregroundStyle(theme.notQuite).font(theme.font(.label))
            case .needsReview: Label("Couldn't read", systemImage: "questionmark.circle").foregroundStyle(theme.attention)
            }
        }
    }
}
