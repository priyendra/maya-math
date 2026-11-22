import Foundation
import SwiftData

/// Claude's proposal for dividing a chapter into lessons.
struct LessonPlanDTO: Codable {
    struct Part: Codable {
        let title: String
        let section_ids: [Int]
        let practice_section_ids: [Int]
    }
    struct Lesson: Codable {
        let title: String
        let summary: String
        let optional: Bool
        let parts: [Part]
    }
    struct Skipped: Codable, Hashable {
        let section_id: Int
        let reason: String
    }
    let lessons: [Lesson]
    let skipped: [Skipped]

    static let schema = Schema.object([
        "lessons": Schema.array(Schema.object([
            "title": Schema.string,
            "summary": Schema.string,
            "optional": Schema.boolean,
            "parts": Schema.array(Schema.object([
                "title": Schema.string,
                "section_ids": Schema.array(Schema.integer),
                "practice_section_ids": Schema.array(Schema.integer),
            ])),
        ])),
        "skipped": Schema.array(Schema.object(["section_id": Schema.integer, "reason": Schema.string])),
    ])
}

/// Divides a chapter into lessons (one Claude call) and makes sure nothing core is left out.
enum LessonPlanner {
    /// What the planner (and the coverage check) knows about one section.
    struct SectionInfo: Equatable {
        let id: Int
        let level: Int
        let title: String
        var parent = -1
        var paragraphs = 0, examples = 0, figures = 0, exercises = 0
        var teachingChars = 0
        var samples: [String] = []
        /// Has explanation or worked examples of its own (must be in a lesson unless deliberately skipped).
        var teaches: Bool { examples > 0 || figures > 0 || teachingChars >= 150 }
    }

    struct Draft: Equatable {
        var title: String
        var summary: String
        var optional: Bool
        var parts: [LessonPart]
    }

    struct Result {
        var lessons: [Draft]
        var skipped: [LessonPlanDTO.Skipped]
        /// Teaching sections Claude left out that were attached to the nearest earlier part.
        var attached: [Int]
    }

    @MainActor
    static func sections(_ chapter: Chapter) -> [SectionInfo] {
        var infos = chapter.outline.map { SectionInfo(id: $0.id, level: $0.level, title: $0.title, parent: $0.parent) }
        let index = Dictionary(uniqueKeysWithValues: infos.enumerated().map { ($1.id, $0) })
        for b in chapter.sortedBlocks {
            guard let i = index[b.sectionID] else { continue }
            switch b.kind {
            case "text": infos[i].paragraphs += 1; infos[i].teachingChars += b.markdown.count
            case "example": infos[i].examples += 1; infos[i].teachingChars += b.markdown.count
            case "figure": infos[i].figures += 1
            case "exercise": infos[i].exercises += 1
            default: break
            }
            if ["text", "example"].contains(b.kind), infos[i].samples.count < 4 {
                let first = b.markdown.split(separator: "\n").first.map(String.init) ?? ""
                infos[i].samples.append((b.kind == "example" ? "Example: " : "") + String(first.prefix(140)))
            }
        }
        return infos
    }

    /// The outline as Claude sees it.
    static func describe(_ title: String, _ sections: [SectionInfo]) -> String {
        var lines = ["Chapter: \(title)", "", "Sections in book order ([id] title — contents):"]
        for s in sections {
            var parts: [String] = []
            if s.paragraphs > 0 { parts.append("\(s.paragraphs) explanation paragraph\(s.paragraphs == 1 ? "" : "s")") }
            if s.examples > 0 { parts.append("\(s.examples) worked example\(s.examples == 1 ? "" : "s")") }
            if s.figures > 0 { parts.append("\(s.figures) figure\(s.figures == 1 ? "" : "s")") }
            if s.exercises > 0 { parts.append("\(s.exercises) exercise\(s.exercises == 1 ? "" : "s")") }
            let indent = String(repeating: "  ", count: s.level)
            lines.append("\(indent)[\(s.id)] \(s.title) — \(parts.isEmpty ? "heading only" : parts.joined(separator: ", "))")
            for sample in s.samples { lines.append("\(indent)    · \(sample)") }
        }
        return lines.joined(separator: "\n")
    }

    /// Cleans up Claude's plan: unknown or repeated sections dropped, empty parts/lessons dropped, and every section
    /// that teaches something is in a part or deliberately skipped (left-out ones join the nearest earlier part).
    static func validate(_ dto: LessonPlanDTO, sections: [SectionInfo]) -> Result {
        let known = Set(sections.map(\.id))
        var seen = Set<Int>()
        func take(_ ids: [Int]) -> [Int] {
            var out: [Int] = []
            for id in ids where known.contains(id) && !seen.contains(id) { seen.insert(id); out.append(id) }
            return out.sorted()
        }
        var lessons: [Draft] = []
        for l in dto.lessons {
            var parts: [LessonPart] = []
            for p in l.parts {
                let teach = take(p.section_ids)
                let practice = take(p.practice_section_ids)
                guard !teach.isEmpty || !practice.isEmpty else { continue }
                parts.append(LessonPart(title: p.title.trimmingCharacters(in: .whitespaces), sectionIDs: teach,
                                        practiceSectionIDs: practice))
            }
            guard !parts.isEmpty else { continue }
            lessons.append(Draft(title: l.title.trimmingCharacters(in: .whitespaces), summary: l.summary,
                                 optional: l.optional, parts: parts))
        }
        var skipped: [LessonPlanDTO.Skipped] = []
        for s in dto.skipped where known.contains(s.section_id) && !seen.contains(s.section_id) {
            seen.insert(s.section_id)
            skipped.append(s)
        }
        var attached: [Int] = []
        // Teaching sections left out of a top-level unit that has no lesson at all become a lesson of their own
        // (one part each); the rest join the nearest earlier part below.
        let byID = Dictionary(uniqueKeysWithValues: sections.map { ($0.id, $0) })
        func root(_ id: Int) -> Int {
            var cur = id
            var guardSteps = 0
            while let p = byID[cur]?.parent, p >= 0, byID[p] != nil, guardSteps < 50 { cur = p; guardSteps += 1 }
            return cur
        }
        let rootsWithLessons = Set(seen.map(root))
        let orphansByRoot = Dictionary(grouping: sections.filter { $0.teaches && !seen.contains($0.id) && !rootsWithLessons.contains(root($0.id)) },
                                       by: { root($0.id) })
        for (r, orphans) in orphansByRoot {
            let parts = orphans.sorted { $0.id < $1.id }.map { LessonPart(title: $0.title, sectionIDs: [$0.id], practiceSectionIDs: []) }
            lessons.append(Draft(title: byID[r]?.title ?? orphans[0].title, summary: "", optional: false, parts: parts))
            for o in orphans { seen.insert(o.id); attached.append(o.id) }
        }
        lessons.sort { ($0.parts.flatMap(\.sectionIDs).min() ?? Int.max) < ($1.parts.flatMap(\.sectionIDs).min() ?? Int.max) }
        if !lessons.isEmpty {
            for s in sections where s.teaches && !seen.contains(s.id) {
                // The part whose sections come last before this one in book order (outline ids are in book order).
                var best: (lesson: Int, part: Int, id: Int)?
                for (li, l) in lessons.enumerated() {
                    for (pi, p) in l.parts.enumerated() {
                        if let m = (p.sectionIDs + p.practiceSectionIDs).filter({ $0 < s.id }).max(), m > (best?.id ?? -1) {
                            best = (li, pi, m)
                        }
                    }
                }
                let (li, pi) = best.map { ($0.lesson, $0.part) } ?? (0, 0)
                lessons[li].parts[pi].sectionIDs = (lessons[li].parts[pi].sectionIDs + [s.id]).sorted()
                seen.insert(s.id)
                attached.append(s.id)
            }
        }
        return Result(lessons: lessons, skipped: skipped, attached: attached)
    }

    /// Plans the chapter's lessons and saves them (replacing any earlier plan).
    @MainActor
    static func plan(_ chapter: Chapter, context: ModelContext, services: ClaudeServices = .live) async throws {
        let infos = sections(chapter)
        guard !infos.isEmpty else { return }
        let dto = try await services.client.structured(
            LessonPlanDTO.self, system: Prompts.lessonPlan,
            content: [.text(describe(chapter.title, infos))],
            schema: LessonPlanDTO.schema, effort: .high, maxTokens: 16000, kind: "lesson_plan")
        let result = validate(dto, sections: infos)
        if !result.attached.isEmpty { CallLog.event("lesson_plan_attached", ["sections": result.attached]) }
        save(result, to: chapter, context: context)
    }

    @MainActor
    static func save(_ result: Result, to chapter: Chapter, context: ModelContext) {
        for l in chapter.lessons { context.delete(l) }
        for (i, d) in result.lessons.enumerated() {
            let lesson = Lesson(order: i, title: d.title, summary: d.summary, optional: d.optional, parts: d.parts)
            lesson.chapter = chapter
            context.insert(lesson)
        }
        chapter.lessonSkippedJSON = (try? String(data: JSONEncoder().encode(result.skipped), encoding: .utf8)) ?? ""
        try? context.save()
    }

    @MainActor
    static func skipped(_ chapter: Chapter) -> [LessonPlanDTO.Skipped] {
        (try? JSONDecoder().decode([LessonPlanDTO.Skipped].self, from: Data(chapter.lessonSkippedJSON.utf8))) ?? []
    }
}
