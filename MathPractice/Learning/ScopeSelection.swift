import Foundation

/// What a study plan takes from one chapter, as saved items (pure logic, unit-tested):
/// - "c|chapter": the whole chapter
/// - "s|chapter|node": a section and everything under it
/// - "n|chapter|node": only the section's own questions, not its subsections (kept when one part of a ticked
///   section is unticked, so questions that sit directly on the section don't silently drop out)
/// - "p|chapter|from|to": a page range
struct ScopeSelection {
    enum Mark { case all, some, none }

    let chapterID: String
    let nodes: [SectionNode]
    var items: Set<String>

    var wholeKey: String { "c|\(chapterID)" }
    func key(_ n: Int) -> String { "s|\(chapterID)|\(n)" }
    func ownKey(_ n: Int) -> String { "n|\(chapterID)|\(n)" }
    /// The chapter's own questions (not in any section) use node -1.
    static let chapterNode = -1

    func children(_ parent: Int) -> [SectionNode] { nodes.filter { $0.parent == parent && $0.id != parent } }
    var roots: [SectionNode] { nodes.filter { !nodes.indices.contains($0.parent) || $0.parent == $0.id } }
    var ranges: [String] { items.filter { $0.hasPrefix("p|\(chapterID)|") }.sorted() }

    func ancestors(_ n: SectionNode) -> [Int] {
        var out: [Int] = [], cur = n.parent
        while nodes.indices.contains(cur), !out.contains(cur) { out.append(cur); cur = nodes[cur].parent }
        return out
    }

    func depth(_ n: SectionNode) -> Int { ancestors(n).count + 1 }

    /// Included through itself, an ancestor or the whole chapter.
    func covered(_ n: SectionNode) -> Bool {
        items.contains(wholeKey) || items.contains(key(n.id)) || ancestors(n).contains { items.contains(key($0)) }
    }

    func mark(_ n: SectionNode) -> Mark {
        if covered(n) { return .all }
        let marks = children(n.id).map(mark)
        if items.contains(ownKey(n.id)) || marks.contains(where: { $0 != .none }) { return .some }
        return .none
    }

    var chapterMark: Mark {
        if items.contains(wholeKey) { return .all }
        let mine = items.contains { $0.hasPrefix("s|\(chapterID)|") || $0.hasPrefix("n|\(chapterID)|") || $0.hasPrefix("p|\(chapterID)|") }
        return mine ? .some : .none
    }

    /// What's picked, in a few words: the top-most included sections, then page ranges.
    var summary: String {
        if items.contains(wholeKey) { return "Whole chapter" }
        var names: [String] = []
        func walk(_ list: [SectionNode]) {
            for n in list {
                switch mark(n) {
                case .all: names.append(MathPlain.render(n.title))
                case .some: walk(children(n.id))
                case .none: break
                }
            }
        }
        walk(roots)
        names += ranges.map(Self.rangeLabel)
        return names.joined(separator: ", ")
    }

    static func rangeLabel(_ item: String) -> String {
        let parts = item.split(separator: "|")
        return parts.count == 4 ? "Pages \(parts[2])–\(parts[3])" : item
    }

    // MARK: Changes

    private mutating func clearSections() {
        items = items.filter { !($0 == wholeKey || $0.hasPrefix("s|\(chapterID)|") || $0.hasPrefix("n|\(chapterID)|")) }
    }

    mutating func toggleChapter() {
        let all = chapterMark == .all
        clearSections()
        if !all { items.insert(wholeKey) }
    }

    private mutating func removeBelow(_ n: SectionNode) {
        items.remove(ownKey(n.id))
        for c in children(n.id) { items.remove(key(c.id)); removeBelow(c) }
    }

    mutating func toggle(_ n: SectionNode) {
        if mark(n) == .all { exclude(n) } else { removeBelow(n); items.insert(key(n.id)) }
        tidy()
    }

    /// Takes a section out. If it was included through an ancestor (or the whole chapter), that ancestor is replaced
    /// by its other parts plus its own questions, so everything else stays in.
    private mutating func exclude(_ n: SectionNode) {
        removeBelow(n)
        if items.remove(key(n.id)) != nil { return }
        let chain = [n.id] + ancestors(n)                       // n, parent, grandparent…
        let top: Int?
        if let t = chain.dropFirst().first(where: { items.contains(key($0)) }) { items.remove(key(t)); top = t }
        else if items.contains(wholeKey) { items.remove(wholeKey); top = nil }
        else { return }
        // Walk down from the removed level to n: keep each level's own questions and every sibling off the path.
        let path = Array(chain.prefix { $0 != top }.reversed())   // from just below top down to n
        items.insert(ownKey(top ?? Self.chapterNode))
        var level = top.map { children($0) } ?? roots
        for step in path {
            for sib in level where sib.id != step { items.insert(key(sib.id)) }
            if step != n.id { items.insert(ownKey(step)) }
            level = children(step)
        }
    }

    /// A section whose parts are all in (and whose own questions are in) becomes the section itself; a chapter whose
    /// sections are all in becomes the whole chapter. Ticking every part means ticking the whole.
    private mutating func tidy() {
        func full(_ n: SectionNode) -> Bool {
            if items.contains(key(n.id)) { return true }
            let kids = children(n.id)
            guard !kids.isEmpty, kids.allSatisfy(full) else { return false }
            return true
        }
        func collapse(_ list: [SectionNode]) {
            for n in list {
                if !items.contains(key(n.id)), full(n) { removeBelow(n); items.insert(key(n.id)) }
                else { collapse(children(n.id)) }
            }
        }
        collapse(roots)
        if !roots.isEmpty, roots.allSatisfy({ items.contains(key($0.id)) }) {
            clearSections(); items.insert(wholeKey)
        }
    }
}
