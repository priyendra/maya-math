import SwiftUI
import SwiftData

/// A study plan: practice and exams limited to the selected material (possibly across chapters).
struct ScopeHomeView: View {
    @Bindable var scope: StudyScope
    @Query(sort: \Chapter.createdAt) private var chapters: [Chapter]
    @State private var editing = false
    @Environment(\.theme) private var theme

    static func countdown(to date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                                   to: Calendar.current.startOfDay(for: date)).day ?? 0
        let when = date.formatted(date: .abbreviated, time: .omitted)
        switch days {
        case ..<0: return "Test was on \(when)"
        case 0: return "Test is today"
        case 1: return "Test is tomorrow"
        default: return "\(days) days to go · test on \(when)"
        }
    }

    var body: some View {
        let set = StudySet.scope(scope, chapters: chapters)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let date = scope.testDate {
                    Label(Self.countdown(to: date), systemImage: "calendar").font(.title3.weight(.semibold))
                }
                Button { editing = true } label: { contents(set) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("planContents")
                StudyActions(set: set)
                // The same tiles and sections as a chapter page (no lessons or reading: those belong to a chapter).
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    NavigationLink { MyAnswersView(set: set) } label: {
                        let toCheck = set.allAttempts.filter { $0.isGraded && $0.effectiveVerdict == .needsReview }.count
                        LinkTile(title: "My answers", subtitle: toCheck > 0 ? "\(toCheck) to check" : "Your work and how it was graded",
                                 icon: "list.bullet.rectangle.fill", highlight: toCheck > 0, color: theme.board)
                    }
                    NavigationLink { ProgressReportView(set: set) } label: {
                        LinkTile(title: "My progress", subtitle: "Skills, mistake patterns, practice days", icon: "chart.bar.fill", color: theme.done)
                    }
                    .accessibilityIdentifier("scopeProgress")
                    Button { editing = true } label: {
                        LinkTile(title: "Edit study plan", subtitle: "What's on the test, test date", icon: "slider.horizontal.3", color: theme.accent2)
                    }
                }
                .buttonStyle(.plain)
                PathGlance(set: set)
                    .padding(20)
                    .card(theme)
                TeacherFeedbackCard(set: set, holder: scope)
            }
            .padding(24)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .themedBackground(theme)
        .navigationTitle(scope.name)
        .sheet(isPresented: $editing) { ScopeEditorView(scope: scope, folder: scope.folder) }
    }

    /// What's in the plan, chapter by chapter (the top-most included sections); tapping it opens the editor.
    private func contents(_ set: StudySet) -> some View {
        let book = set.questions.filter { $0.source == .book }.count
        let items = Set(scope.items)
        let picked = chapters.filter { c in items.contains { $0.hasSuffix("|\(c.id.uuidString)") || $0.contains("|\(c.id.uuidString)|") } }
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("What's in it · \(book) questions").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                if picked.isEmpty { Text("Nothing yet").foregroundStyle(.secondary) }
                ForEach(picked) { c in
                    (Text(MathPlain.render(c.title)).fontWeight(.semibold)
                     + Text(" — " + ScopeChapterPicker(chapter: c, items: .constant(items)).summary).foregroundStyle(.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.secondary).padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(theme)
        .contentShape(Rectangle())
    }
}

/// Create or edit a study plan: name, optional test date, exam length, and what's in it.
struct ScopeEditorView: View {
    let scope: StudyScope?
    let folder: Folder?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Chapter.createdAt) private var chapters: [Chapter]

    @State private var name = ""
    @State private var hasDate = false
    @State private var date = Date().addingTimeInterval(14 * 86_400)
    @State private var minutes = 30
    @State private var items: Set<String> = []
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Unit 5 test)", text: $name)
                    Toggle("Test date", isOn: $hasDate)
                    if hasDate { DatePicker("Date", selection: $date, displayedComponents: .date) }
                }
                Section {
                    ForEach(chapters.filter { $0.status == .ready && !$0.needsRereading }) { chapter in
                        ScopeChapterPicker(chapter: chapter, items: $items)
                    }
                } header: {
                    Text("What's in it")
                } footer: {
                    Text("Tick a chapter or any of its sections. Tap a row to open it.")
                }
                if chapters.contains(where: \.needsRereading) {
                    Section { Text("Chapters that haven't been re-read with the new reader can't be split by section yet.").font(.caption) }
                }
            }
            .navigationTitle(scope == nil ? "New study plan" : "Edit study plan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || items.isEmpty)
                }
            }
            .onAppear(perform: load)
        }
        .largeSheet()
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let scope else { return }
        name = scope.name
        hasDate = scope.testDate != nil
        if let d = scope.testDate { date = d }
        minutes = scope.examMinutes
        items = Set(scope.items)
    }

    private func save() {
        let target = scope ?? {
            let s = StudyScope(name: name)
            s.folder = folder
            context.insert(s)
            return s
        }()
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.testDate = hasDate ? date : nil
        target.examMinutes = minutes
        let newItems = Array(items).sorted()
        // Different material: the teacher's feedback is written again on the next visit (the old one shows until then).
        if scope != nil && target.items != newItems { target.feedbackAtSeconds = -1 }
        target.items = newItems
        try? context.save()
        dismiss()
    }
}

/// One chapter in the study plan editor: a foldable section tree with checkboxes (all / some / none).
/// The selection rules live in ScopeSelection.
struct ScopeChapterPicker: View {
    let chapter: Chapter
    @Binding var items: Set<String>
    @State private var expanded: Set<Int> = []
    @State private var open = false
    @State private var pagesOpen = false
    @State private var pageFrom = ""
    @State private var pageTo = ""

    typealias Mark = ScopeSelection.Mark

    private var cid: String { chapter.id.uuidString }
    private var sel: ScopeSelection { ScopeSelection(chapterID: cid, nodes: chapter.outline, items: items) }
    var summary: String { sel.summary }

    var body: some View {
        let s = sel
        row(title: MathPlain.render(chapter.title), subtitle: s.summary, level: 0, mark: s.chapterMark,
            canOpen: true, isOpen: open, bold: true,
            toggleOpen: { withAnimation { open.toggle() } }, toggleMark: { change { $0.toggleChapter() } })
        if open {
            ForEach(visible(s), id: \.id) { n in
                let kids = !s.children(n.id).isEmpty
                row(title: MathPlain.render(n.title), subtitle: nil, level: s.depth(n), mark: s.mark(n),
                    canOpen: kids, isOpen: expanded.contains(n.id), bold: kids,
                    toggleOpen: { withAnimation { if expanded.contains(n.id) { expanded.remove(n.id) } else { expanded.insert(n.id) } } },
                    toggleMark: { change { $0.toggle(n) } })
            }
            pagesRow(s.ranges)
        }
    }

    private func change(_ f: (inout ScopeSelection) -> Void) {
        var s = sel
        f(&s)
        items = s.items
    }

    /// Nodes shown: roots, plus the children of every open node (in book order).
    private func visible(_ s: ScopeSelection) -> [SectionNode] {
        var out: [SectionNode] = []
        func walk(_ list: [SectionNode]) {
            for n in list {
                out.append(n)
                if expanded.contains(n.id) { walk(s.children(n.id)) }
            }
        }
        walk(s.roots)
        return out
    }

    // MARK: Rows

    private func row(title: String, subtitle: String?, level: Int, mark: Mark, canOpen: Bool, isOpen: Bool, bold: Bool,
                     toggleOpen: @escaping () -> Void, toggleMark: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button(action: toggleMark) {
                Image(systemName: mark == .all ? "checkmark.circle.fill" : mark == .some ? "minus.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(mark == .none ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(mark == .all ? "Included" : mark == .some ? "Partly included" : "Not included")
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(bold ? .body.weight(.semibold) : .body)
                    .accessibilityIdentifier("scopeRow-\(title)")
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if canOpen {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
            }
        }
        .padding(.leading, CGFloat(level) * 28)
        .contentShape(Rectangle())
        .onTapGesture { if canOpen { toggleOpen() } else { toggleMark() } }
    }

    @ViewBuilder
    private func pagesRow(_ ranges: [String]) -> some View {
        row(title: "Page ranges", subtitle: ranges.isEmpty ? nil : ranges.map(ScopeSelection.rangeLabel).joined(separator: ", "),
            level: 1, mark: ranges.isEmpty ? .none : .all, canOpen: true, isOpen: pagesOpen, bold: false,
            toggleOpen: { withAnimation { pagesOpen.toggle() } }, toggleMark: { withAnimation { pagesOpen.toggle() } })
        if pagesOpen {
            ForEach(ranges, id: \.self) { item in
                HStack {
                    Text(ScopeSelection.rangeLabel(item))
                    Spacer()
                    Button(role: .destructive) { items.remove(item) } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.borderless)
                }
                .padding(.leading, 56)
            }
            HStack {
                Text("Pages")
                TextField("from", text: $pageFrom).keyboardType(.numberPad).frame(width: 70).textFieldStyle(.roundedBorder)
                Text("to")
                TextField("to", text: $pageTo).keyboardType(.numberPad).frame(width: 70).textFieldStyle(.roundedBorder)
                Button("Add range") {
                    if let a = Int(pageFrom), let b = Int(pageTo) {
                        items.insert("p|\(cid)|\(min(a, b))|\(max(a, b))")
                        pageFrom = ""; pageTo = ""
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(.leading, 56)
        }
    }
}

extension View {
    /// A tall sheet on iPad (page-sized where available) so long lists don't scroll inside a small window.
    @ViewBuilder func largeSheet() -> some View {
        if #available(iOS 18.0, *) { presentationSizing(.page) } else { self }
    }
}
