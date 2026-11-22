import SwiftUI
import PencilKit

/// A lesson on one canvas page: each part's book content appears as the tutor explains it, with a cursor and a
/// board; she can write anywhere, ask at any time, and answers "your turn" problems under them.
struct LessonPage: View {
    let lesson: Lesson
    var onNext: ((Lesson) -> Void)? = nil
    @StateObject private var tutor: LessonSession
    @StateObject private var ink = PageInk()
    @State private var practicing = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.theme) private var theme

    init(lesson: Lesson, onNext: ((Lesson) -> Void)? = nil) {
        self.lesson = lesson
        self.onNext = onNext
        _tutor = StateObject(wrappedValue: LessonSession(lesson: lesson))
    }

    var body: some View {
        NavigationStack {
            InkPageView(ink: ink)
                .background(theme.background)
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
            ink.onInk = { [weak tutor] in tutor?.inkChanged() }
            ink.onTap = { [weak tutor] in tutor?.interrupt() }
            tutor.snapshot = { [weak ink] in ink?.snapshot() }
            tutor.workBelow = { [weak ink] id in ink?.work(below: id) }
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
                Button { ink.clear() } label: { Image(systemName: "trash").frame(width: 36, height: 36) }
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
                        Text(tutor.caption).lineLimit(2)
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
            if tutor.state == .listening || tutor.state.isWaiting || tutor.phase == .questions {
                Button { tutor.goOn() } label: { Label("Go on", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("lessonGoOn")
            }
        case .preparing, .checking:
            EmptyView()
        }
    }

    private var nextLesson: Lesson? {
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
            Text("Room to write ↓").font(.caption).foregroundStyle(.tertiary)
            Color.clear.frame(height: 420)
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
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PART \(part + 1)").font(theme.font(.caption).weight(.bold)).kerning(1).foregroundStyle(theme.learn)
                    Text(MathPlain.render(title)).font(theme.font(.pageTitle))
                }
                .padding(.top, part == 0 ? 0 : 18)
                .part(e.id)
            }
        case let .item(item):
            itemView(item).part(item.id)
        case let .board(b):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "pencil.line").foregroundStyle(theme.board)
                MathText(markdown: b.markdown, fontSize: 21)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .card(theme, tint: theme.board, radius: min(theme.radius, 12))
            .part(b.id)
        case let .turn(id, qid):
            if let q = tutor.questionsByID[qid] {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Your turn", systemImage: "pencil.and.outline").font(theme.font(.cardTitle)).foregroundStyle(theme.done)
                        Spacer()
                        if !q.printedNumber.isEmpty { Text("Book #\(q.printedNumber)").font(.caption).foregroundStyle(.secondary) }
                        if let a = tutor.answers[id] { verdict(a) }
                    }
                    QuestionPanel(question: q)
                }
                .padding(16)
                .card(theme, tint: theme.done)
                .overlay(RoundedRectangle(cornerRadius: theme.radius, style: .continuous).stroke(theme.done.opacity(0.4), lineWidth: 1.5))
                .part(id)
                Color.clear.frame(height: 260).part(id + "_room")   // room for her answer
            }
        case .finished:
            VStack(alignment: .leading, spacing: 6) {
                Label("Lesson done!", systemImage: "party.popper.fill").font(theme.font(.section)).foregroundStyle(theme.done)
                let results = tutor.answers.values.sorted { $0.startedAt < $1.startedAt }
                if !results.isEmpty {
                    Text("Your turns: " + results.map { $0.effectiveVerdict == .correct ? "✓" : $0.effectiveVerdict == .incorrect ? "✗" : "?" }.joined(separator: "  "))
                        .font(.headline)
                }
            }
            .padding(18)
            .card(theme, tint: theme.done)
            .part(e.id)
        }
    }

    @ViewBuilder private func itemView(_ item: LessonPartScript.Item) -> some View {
        switch item.kind {
        case "heading":
            MathText(markdown: "**\(item.markdown)**", fontSize: 21)
        case "example":
            MathText(markdown: item.markdown, fontSize: 21)
                .padding(.leading, 16)
                .overlay(alignment: .leading) { Capsule().fill(theme.attention).frame(width: 4) }
        case "figure":
            VStack(alignment: .leading, spacing: 4) {
                if let id = item.blockID, let data = tutor.lesson.chapter?.blocks.first(where: { $0.id == id })?.imageData,
                   let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().scaledToFit().frame(maxWidth: 560, maxHeight: 360, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                if !item.markdown.isEmpty { MathText(markdown: item.markdown, fontSize: 16) }
            }
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
