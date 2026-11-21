import SwiftUI
import SwiftData
import WebKit

/// The digital chapter: section list on the left, the selected section typeset on the right.
/// Tap an exercise to see its tags, include/exclude it, see your answers, or practice it.
struct ReadChapterView: View {
    let chapter: Chapter
    @State private var selected: Int?
    @State private var tapped: Question?

    var body: some View {
        let nodes = chapter.outline
        HStack(spacing: 0) {
            List(nodes, selection: $selected) { node in
                Text(node.title)
                    .font(node.level == 1 ? .body.weight(.semibold) : .callout)
                    .padding(.leading, CGFloat(node.level - 1) * 14)
                    .tag(Optional(node.id))
            }
            .listStyle(.sidebar)
            .frame(width: 300)
            Divider()
            ChapterWebView(html: html(for: selected ?? nodes.first?.id ?? -1)) { id in
                tapped = chapter.questions.first { $0.id.uuidString == id }
            }
        }
        .navigationTitle(chapter.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if selected == nil { selected = nodes.first?.id } }
        .sheet(item: $tapped) { q in NavigationStack { QuestionDetailView(question: q) } }
    }

    /// Blocks of this section and its subsections, in reading order.
    private func html(for section: Int) -> String {
        let nodes = chapter.outline
        let blocks = chapter.sortedBlocks.filter { section < 0 || StudySet.isWithin($0.sectionID, section, nodes) }
        let questions = Dictionary(uniqueKeysWithValues: chapter.questions.map { ($0.id, $0) })
        let pageNumbers = Dictionary(uniqueKeysWithValues: chapter.pages.map { ($0.order, $0.printedPageNumber) })
        var items: [[String: Any]] = []
        var lastPage: Int?
        var lastSection = -2
        for b in blocks {
            if b.pageIndex != lastPage {
                lastPage = b.pageIndex
                let label = pageNumbers[b.pageIndex].flatMap { $0 }.map { "Page \($0)" } ?? "Scan page \(b.pageIndex + 1)"
                items.append(["kind": "page", "text": label])
            }
            if b.sectionID != lastSection, nodes.indices.contains(b.sectionID), b.sectionID != section {
                lastSection = b.sectionID
                items.append(["kind": "section", "text": nodes[b.sectionID].title, "level": nodes[b.sectionID].level])
            }
            var item: [String: Any] = ["kind": b.kind, "md": b.markdown, "num": b.printedNumber]
            if let img = b.imageData { item["img"] = "data:image/jpeg;base64," + img.base64EncodedString() }
            if let qid = b.questionID, let q = questions[qid] {
                item["id"] = qid.uuidString
                var tags: [String] = []
                if !q.isIncluded { tags.append(q.pencilOK ? "excluded" : "not doable with a pencil") }
                if q.isChallenge { tags.append("challenge") }
                item["tags"] = tags
                item["excluded"] = !q.isIncluded
                let last = q.gradedAttempts.last?.effectiveVerdict
                item["status"] = last == .correct ? "right" : (last == .incorrect ? "wrong" : (q.attempts.isEmpty ? "" : "pending"))
            }
            items.append(item)
        }
        let title = nodes.indices.contains(section) ? nodes[section].title : chapter.title
        return ChapterWebView.document(title: title, items: items)
    }
}

struct ChapterWebView: UIViewRepresentable {
    let html: String
    let onTapQuestion: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTapQuestion) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "tap")
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .systemBackground
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.onTap = onTapQuestion
        guard context.coordinator.loaded != html else { return }
        context.coordinator.loaded = html
        view.loadHTMLString(html, baseURL: Bundle.main.url(forResource: "katex", withExtension: nil))
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "tap")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var onTap: (String) -> Void
        var loaded: String?
        init(onTap: @escaping (String) -> Void) { self.onTap = onTap }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if let id = message.body as? String { onTap(id) }
        }
    }

    static func document(title: String, items: [[String: Any]]) -> String {
        let json = (try? String(data: JSONSerialization.data(withJSONObject: items), encoding: .utf8)) ?? "[]"
        let titleJSON = (try? String(data: JSONSerialization.data(withJSONObject: [title]), encoding: .utf8)) ?? "[\"\"]"
        return """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <link rel="stylesheet" href="katex.min.css">
        <script src="katex.min.js"></script>
        <script src="marked.min.js"></script>
        <style>
          :root { color-scheme: light dark; --fg:#1c1c1e; --muted:#6e6e73; --card:#f2f2f7; --accent:#0a84ff; --line:#d1d1d6; }
          @media (prefers-color-scheme: dark) { :root { --fg:#f2f2f7; --muted:#a1a1a6; --card:#1c1c1e; --line:#3a3a3c; } }
          body { margin: 0; padding: 28px 40px 80px; font-family: -apple-system, sans-serif; font-size: 19px;
                 line-height: 1.5; color: var(--fg); background: transparent; -webkit-text-size-adjust: none; }
          h1 { font-size: 30px; margin: 0 0 12px; }
          h2 { font-size: 24px; margin: 28px 0 8px; } h3 { font-size: 20px; margin: 22px 0 6px; }
          .page { color: var(--muted); font-size: 13px; text-transform: uppercase; letter-spacing: .05em;
                  border-top: 1px solid var(--line); margin: 28px 0 10px; padding-top: 6px; }
          .example { background: var(--card); border-left: 4px solid #ff9f0a; border-radius: 10px; padding: 12px 16px; margin: 12px 0; }
          .example::before { content: "Example"; display: block; font-weight: 700; color: #ff9f0a; font-size: 14px; }
          .exercise { display: flex; gap: 12px; padding: 10px 12px; margin: 6px 0; border-radius: 10px; cursor: pointer; }
          .exercise:active { background: var(--card); }
          .num { min-width: 34px; font-weight: 700; color: var(--accent); }
          .exercise.excluded { opacity: .45; }
          .tag { display: inline-block; font-size: 12px; font-weight: 600; padding: 1px 8px; border-radius: 10px;
                 background: var(--card); color: var(--muted); margin-left: 6px; }
          .tag.challenge { color: #ff453a; }
          .st { margin-left: auto; font-size: 18px; } .st.right::after { content: "✓"; color: #30d158; }
          .st.wrong::after { content: "✗"; color: #ff453a; } .st.pending::after { content: "…"; color: var(--muted); }
          img { max-width: min(100%, 520px); display: block; margin: 8px 0; border-radius: 6px; background: white; }
          figure { margin: 12px 0; } figcaption { color: var(--muted); font-size: 15px; }
          p { margin: 0 0 .5em; } p:last-child { margin-bottom: 0; }
          table { border-collapse: collapse; } td, th { border: 1px solid var(--line); padding: 4px 10px; }
          .katex-display { margin: .4em 0; overflow-x: auto; overflow-y: hidden; }
        </style></head><body><h1 id="t"></h1><div id="c"></div>
        <script>
          function render(src) {
            const math = [];
            let s = (src || '').replace(/\\$\\$([\\s\\S]+?)\\$\\$/g, (_, m) => { math.push([m, true]); return '@@M' + (math.length - 1) + '@@'; })
                       .replace(/\\$([^$\\n]+?)\\$/g, (_, m) => { math.push([m, false]); return '@@M' + (math.length - 1) + '@@'; });
            let html = marked.parse(s, { breaks: true });
            return html.replace(/@@M(\\d+)@@/g, (_, i) => {
              const [m, d] = math[+i];
              try { return katex.renderToString(m, { displayMode: d, throwOnError: false }); } catch (e) { return m; }
            });
          }
          function esc(t) { const d = document.createElement('div'); d.textContent = t; return d.innerHTML; }
          document.getElementById('t').textContent = \(titleJSON)[0];
          const items = \(json);
          const out = [];
          for (const it of items) {
            const img = it.img ? '<img src="' + it.img + '">' : '';
            switch (it.kind) {
              case 'page': out.push('<div class="page">' + esc(it.text) + '</div>'); break;
              case 'section': out.push(it.level <= 1 ? '<h2>' + esc(it.text) + '</h2>' : '<h3>' + esc(it.text) + '</h3>'); break;
              case 'heading': out.push('<h3>' + render(it.md) + '</h3>'); break;
              case 'example': out.push('<div class="example">' + render(it.md) + img + '</div>'); break;
              case 'figure': out.push('<figure>' + img + '<figcaption>' + render(it.md) + '</figcaption></figure>'); break;
              case 'exercise': {
                const tags = (it.tags || []).map(t => '<span class="tag ' + (t === 'challenge' ? 'challenge' : '') + '">' + esc(t) + '</span>').join('');
                out.push('<div class="exercise' + (it.excluded ? ' excluded' : '') + '" data-id="' + (it.id || '') + '">' +
                         '<div class="num">' + esc(it.num || '•') + '</div><div>' + render(it.md) + img + tags + '</div>' +
                         '<div class="st ' + (it.status || '') + '"></div></div>');
                break;
              }
              default: out.push('<div>' + render(it.md) + img + '</div>');
            }
          }
          document.getElementById('c').innerHTML = out.join('');
          document.querySelectorAll('.exercise').forEach(el => el.addEventListener('click', () => {
            if (el.dataset.id) window.webkit.messageHandlers.tap.postMessage(el.dataset.id);
          }));
        </script></body></html>
        """
    }
}

/// One exercise: its tags, include/exclude, your answers, and practicing it.
struct QuestionDetailView: View {
    @Bindable var question: Question
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var practicing = false
    @State private var showPage = false

    private enum Use: String, CaseIterable { case automatic, always, never }

    private var use: Binding<Use> {
        Binding(get: {
            switch question.includeOverride { case .some(true): return .always; case .some(false): return .never; case .none: return .automatic }
        }, set: { v in
            question.includeOverride = v == .automatic ? nil : (v == .always)
            if let chapter = question.chapter { ChapterProcessor.shared.ensureSkills(chapter, context: context) }
            try? context.save()
        })
    }

    var body: some View {
        Form {
            Section {
                QuestionPanel(question: question)
                if question.pageIndex != nil { Button("Show the scanned page") { showPage = true } }
            }
            Section("About this question") {
                if let chapter = question.chapter, chapter.outline.indices.contains(question.sectionID) {
                    LabeledContent("Section", value: ChapterProcessor.sectionTitle(question.sectionID, chapter.outline))
                }
                if !question.printedNumber.isEmpty { LabeledContent("Exercise", value: question.printedNumber) }
                if let p = question.printedPage { LabeledContent("Page", value: "\(p)") }
                LabeledContent("Concept", value: question.concept?.name ?? "—")
                LabeledContent("Difficulty", value: ["Basic", "Medium", "Hard"][max(0, min(2, question.difficulty - 1))])
                if question.isChallenge { LabeledContent("Challenge", value: "Yes — practiced as a stretch, never on exams") }
                if let key = question.answerKeyAnswer, !key.isEmpty { LabeledContent("Book answer", value: key) }
            }
            Section {
                Picker("Use in practice", selection: use) {
                    Text(question.pencilOK ? "Automatic (yes)" : "Automatic (no)").tag(Use.automatic)
                    Text("Always").tag(Use.always)
                    Text("Never").tag(Use.never)
                }
                if !question.pencilOK {
                    Text("Left out because it needs more than a pencil" + (question.pencilReason.isEmpty ? "." : ": \(question.pencilReason)."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if question.status == .retired, let note = question.reviewNote {
                    Text(note).font(.caption).foregroundStyle(.orange)
                }
                Button("Practice this question") { practicing = true }.disabled(!question.isAvailable)
            }
            let attempts = question.attempts.sorted { $0.startedAt > $1.startedAt }
            if !attempts.isEmpty {
                Section("Your answers") {
                    ForEach(attempts) { a in
                        NavigationLink { AttemptReviewView(attempt: a) } label: {
                            HStack {
                                if a.isGraded { VerdictBadge(verdict: a.effectiveVerdict) } else { ProgressView() }
                                Text(a.startedAt.formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                    }
                }
            }
            Section { ReportProblemButton(subject: .question(question)) }
        }
        .navigationTitle(question.printedNumber.isEmpty ? "Exercise" : "Exercise \(question.printedNumber)")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .fullScreenCover(isPresented: $practicing) {
            if let chapter = question.chapter { PracticeSessionView(set: .chapter(chapter), startQuestionID: question.id) }
        }
        .sheet(isPresented: $showPage) {
            if let chapter = question.chapter, let index = question.pageIndex,
               let page = chapter.sortedPages.first(where: { $0.order == index }), let image = UIImage(data: page.imageData) {
                ScrollView { Image(uiImage: image).resizable().scaledToFit() }
            }
        }
    }
}
