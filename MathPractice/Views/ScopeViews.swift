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
                Text(summary(set)).foregroundStyle(.secondary)
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

    private func summary(_ set: StudySet) -> String {
        let book = set.questions.filter { $0.source == .book }.count
        let names = set.chapters.map { MathPlain.render($0.title) }.joined(separator: ", ")
        return "\(book) questions from \(names.isEmpty ? "no chapters yet" : names)"
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
    @State private var pageFrom: [UUID: String] = [:]
    @State private var pageTo: [UUID: String] = [:]
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Unit 5 test)", text: $name)
                    Toggle("Test date", isOn: $hasDate)
                    if hasDate { DatePicker("Date", selection: $date, displayedComponents: .date) }
                }
                ForEach(chapters.filter { $0.status == .ready && !$0.needsRereading }) { chapter in
                    Section(MathPlain.render(chapter.title)) { chapterPicker(chapter) }
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
    }

    @ViewBuilder
    private func chapterPicker(_ chapter: Chapter) -> some View {
        let id = chapter.id.uuidString
        let whole = "c|\(id)"
        Toggle("Whole chapter", isOn: binding(whole))
        if !items.contains(whole) {
            ForEach(chapter.outline) { node in
                let key = "s|\(id)|\(node.id)"
                Toggle(isOn: binding(key)) {
                    Text(MathPlain.render(node.title)).font(node.level == 1 ? .body.weight(.semibold) : .body)
                }
                .padding(.leading, CGFloat(node.level - 1) * 24)
                .disabled(ancestorSelected(node, chapter))
            }
            ForEach(Array(items.filter { $0.hasPrefix("p|\(id)|") }).sorted(), id: \.self) { item in
                let parts = item.split(separator: "|")
                HStack {
                    Text("Pages \(parts[2])–\(parts[3])")
                    Spacer()
                    Button(role: .destructive) { items.remove(item) } label: { Image(systemName: "minus.circle.fill") }
                }
            }
            HStack {
                Text("Pages")
                TextField("from", text: Binding(get: { pageFrom[chapter.id] ?? "" }, set: { pageFrom[chapter.id] = $0 }))
                    .keyboardType(.numberPad).frame(width: 70).textFieldStyle(.roundedBorder)
                Text("to")
                TextField("to", text: Binding(get: { pageTo[chapter.id] ?? "" }, set: { pageTo[chapter.id] = $0 }))
                    .keyboardType(.numberPad).frame(width: 70).textFieldStyle(.roundedBorder)
                Button("Add range") {
                    if let a = Int(pageFrom[chapter.id] ?? ""), let b = Int(pageTo[chapter.id] ?? "") {
                        items.insert("p|\(id)|\(min(a, b))|\(max(a, b))")
                        pageFrom[chapter.id] = nil; pageTo[chapter.id] = nil
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func ancestorSelected(_ node: SectionNode, _ chapter: Chapter) -> Bool {
        var cur = node.parent
        let nodes = chapter.outline
        while nodes.indices.contains(cur) {
            if items.contains("s|\(chapter.id.uuidString)|\(cur)") { return true }
            cur = nodes[cur].parent
        }
        return false
    }

    private func binding(_ key: String) -> Binding<Bool> {
        Binding(get: { items.contains(key) }, set: { on in if on { items.insert(key) } else { items.remove(key) } })
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
        target.items = Array(items).sorted()
        try? context.save()
        dismiss()
    }
}
