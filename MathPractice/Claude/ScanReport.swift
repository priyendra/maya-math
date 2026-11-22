import Foundation
import SwiftData

/// One thing to fix after the pages were read: a page to scan again, missing pages, or a page scanned twice.
struct ScanIssue: Identifiable {
    enum Kind {
        /// Claude couldn't read all of this page; details are kid-friendly ("the bottom is cut off …").
        case badPage(PageImage, details: [String])
        /// Printed page numbers jump from `after` to a later page: pages from…to are missing.
        case missing(from: Int, to: Int, after: PageImage?)
        /// The same printed page appears twice; `extra` is the copy to drop.
        case duplicate(number: Int, extra: PageImage)
    }
    let id: String
    let kind: Kind
}

@MainActor
enum ScanReport {
    /// Issues found on pages read so far (unread, newly scanned pages are not judged yet).
    static func issues(_ chapter: Chapter) -> [ScanIssue] {
        let pages = chapter.sortedPages
        var out: [ScanIssue] = []
        var problemsByPage: [UUID: [ReadDTO.ScanProblem]] = [:]
        for p in pages {
            guard let dto = ChapterProcessor.decodePage(p) else { continue }
            let problems = dto.scan_problems ?? []
            problemsByPage[p.id] = problems
            if !problems.isEmpty {
                out.append(ScanIssue(id: "page-\(p.id)", kind: .badPage(p, details: problems.map(\.detail))))
            }
        }
        // Numbering, over read content pages in order.
        let content = pages.filter { !$0.isAnswerKey && $0.readJSON != nil }
        var prev: PageImage?
        for p in content {
            guard let n = p.printedPageNumber else { continue }
            if let pp = prev, let m = pp.printedPageNumber {
                if n == m {
                    // Keep the better copy (fewer problems); drop the other.
                    let extra = (problemsByPage[p.id]?.count ?? 0) >= (problemsByPage[pp.id]?.count ?? 0) ? p : pp
                    out.removeAll { if case let .badPage(bp, _) = $0.kind { return bp.id == extra.id } else { return false } }
                    out.append(ScanIssue(id: "dup-\(n)-\(extra.id)", kind: .duplicate(number: n, extra: extra)))
                    if extra.id == pp.id { prev = p }
                    continue
                }
                if n > m + 1 {
                    out.append(ScanIssue(id: "missing-\(m + 1)", kind: .missing(from: m + 1, to: n - 1, after: pp)))
                }
            }
            prev = p
        }
        return out
    }

    /// Pages scanned since the last check, waiting to be read.
    static func pendingCount(_ chapter: Chapter) -> Int { chapter.pages.filter { $0.readJSON == nil }.count }

    /// True when the gap after `after` already has newly scanned (unread) pages in it.
    static func gapFilled(after: PageImage?, in chapter: Chapter) -> Bool {
        let pages = chapter.sortedPages
        let i = after.flatMap { a in pages.firstIndex { $0.id == a.id } } ?? -1
        return pages.indices.contains(i + 1) && pages[i + 1].readJSON == nil
    }

    /// Puts content pages in book order by their printed page numbers (kids don't always scan in order). Only when
    /// every content page has a number it read itself; answer-key pages go after, in scan order. Returns true if
    /// anything moved.
    @discardableResult
    static func sortByPageNumber(_ chapter: Chapter) -> Bool {
        let pages = chapter.sortedPages
        let content = pages.filter { !$0.isAnswerKey }
        let numbers = content.map { p in ChapterProcessor.decodePage(p).map(\.printed_page_number) ?? 0 }
        guard !content.isEmpty, numbers.allSatisfy({ $0 > 0 }) else { return false }
        let sorted = zip(content, numbers).enumerated()
            .sorted { ($0.element.1, $0.offset) < ($1.element.1, $1.offset) }
            .map(\.element.0)
        let ordered = sorted + pages.filter(\.isAnswerKey)
        guard ordered.map(\.id) != pages.map(\.id) else { return false }
        for (i, p) in ordered.enumerated() { p.order = i }
        return true
    }
}

// MARK: - Fixing scans

extension ChapterProcessor {
    /// A new photo for a page that couldn't be read well. It is read again on the next check.
    func replacePage(_ page: PageImage, with jpeg: Data, context: ModelContext) {
        page.imageData = jpeg
        page.readJSON = nil
        page.printedPageNumber = nil
        try? context.save()
    }

    /// Newly scanned pages go right after `after` (or first). Book order is restored by page number after reading.
    func insertPages(_ jpegs: [Data], after: PageImage?, in chapter: Chapter, context: ModelContext) {
        guard !jpegs.isEmpty else { return }
        let start = (after?.order ?? -1) + 1
        for p in chapter.pages where p.order >= start { p.order += jpegs.count }
        for (i, jpeg) in jpegs.enumerated() {
            let page = PageImage(order: start + i, imageData: jpeg, isAnswerKey: false)
            page.chapter = chapter
            context.insert(page)
        }
        try? context.save()
    }

    func removePage(_ page: PageImage, from chapter: Chapter, context: ModelContext) {
        context.delete(page)
        for (i, p) in chapter.sortedPages.filter({ $0.id != page.id }).enumerated() { p.order = i }
        try? context.save()
    }

    /// Build the chapter without fixing the remaining scan issues.
    func continueAnyway(_ chapter: Chapter, context: ModelContext) {
        chapter.scanIssuesAccepted = true
        try? context.save()
        start(chapter, context: context)
    }
}
