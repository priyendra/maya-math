import XCTest
import SwiftData
import UIKit
@testable import MathPractice

@MainActor
final class ScanTests: XCTestCase {
    private func chapter(_ numbers: [Int], problems: [Int: String] = [:]) throws -> (ModelContext, Chapter) {
        let container = try ModelContainer(for: Chapter.self, PageImage.self, Concept.self, Question.self, Attempt.self,
                                           SkillState.self, ExamSession.self, ContentBlock.self, TutorTurn.self, Lesson.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let ch = Chapter(title: "T")
        context.insert(ch)
        for (i, n) in numbers.enumerated() {
            let p = PageImage(order: i, imageData: Data([UInt8(i)]))
            let probs = problems[n].map { [ReadDTO.ScanProblem(kind: "blurry", detail: $0)] } ?? []
            let dto = ReadDTO.Page(image_number: 1, printed_page_number: n, is_answer_key: false, blocks: [], scan_problems: probs)
            p.readJSON = String(data: try JSONEncoder().encode(dto), encoding: .utf8)
            p.chapter = ch
            context.insert(p)
        }
        _ = ChapterProcessor.checkPageNumbers(ch.sortedPages)
        objc_setAssociatedObject(ch, "keep", container, .OBJC_ASSOCIATION_RETAIN)
        return (context, ch)
    }

    func testPagesScannedOutOfOrderAreSorted() throws {
        let (_, ch) = try chapter([212, 214, 213, 215])
        XCTAssertTrue(ScanReport.sortByPageNumber(ch))
        _ = ChapterProcessor.checkPageNumbers(ch.sortedPages)
        XCTAssertEqual(ch.sortedPages.map(\.printedPageNumber), [212, 213, 214, 215])
        XCTAssertTrue(ScanReport.issues(ch).isEmpty)
        XCTAssertFalse(ScanReport.sortByPageNumber(ch), "already in order")
    }

    func testIssuesListBadMissingAndDuplicatePages() throws {
        let (_, ch) = try chapter([212, 213, 216, 216, 217], problems: [213: "the right half is blurry"])
        let issues = ScanReport.issues(ch)
        var bad = 0, missing: [(Int, Int)] = [], dups: [Int] = []
        for i in issues {
            switch i.kind {
            case let .badPage(p, details): bad += 1; XCTAssertEqual(p.printedPageNumber, 213); XCTAssertEqual(details, ["the right half is blurry"])
            case let .missing(from, to, after): missing.append((from, to)); XCTAssertEqual(after?.printedPageNumber, 213)
            case let .duplicate(n, _): dups.append(n)
            }
        }
        XCTAssertEqual(bad, 1)
        XCTAssertEqual(missing.map(\.0), [214]); XCTAssertEqual(missing.map(\.1), [215])
        XCTAssertEqual(dups, [216])
    }

    func testRescannedPagesGoIntoTheGapAndWaitToBeRead() throws {
        let (context, ch) = try chapter([212, 213, 216])
        let after = ch.sortedPages[1]
        XCTAssertFalse(ScanReport.gapFilled(after: after, in: ch))
        ChapterProcessor.shared.insertPages([Data([9]), Data([10])], after: after, in: ch, context: context)
        XCTAssertEqual(ch.sortedPages.map(\.order), [0, 1, 2, 3, 4])
        XCTAssertEqual(ch.sortedPages[2].imageData, Data([9]))
        XCTAssertEqual(ch.sortedPages[4].printedPageNumber, 216)
        XCTAssertTrue(ScanReport.gapFilled(after: after, in: ch))
        XCTAssertEqual(ScanReport.pendingCount(ch), 2)
        ChapterProcessor.shared.replacePage(ch.sortedPages[0], with: Data([7]), context: context)
        XCTAssertEqual(ScanReport.pendingCount(ch), 3)
    }

    func testReadsPrintedPageNumberAtTheBottom() throws {
        let page = UIGraphicsImageRenderer(size: CGSize(width: 1700, height: 2200)).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 1700, height: 2200))
            for row in 0..<30 {
                ("\(row + 1). Solve 4x − \(row) = 2x + 9 and check your answer" as NSString)
                    .draw(at: CGPoint(x: 120, y: 160 + row * 55), withAttributes: [.font: UIFont.systemFont(ofSize: 30)])
            }
            ("293" as NSString).draw(at: CGPoint(x: 1500, y: 2110), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 34)])
        }.cgImage!
        XCTAssertEqual(ScanQuality.measure(page).pageNumber, 293)
    }

    func testOnDeviceCheckFlagsBlurNotSharpText() throws {
        let sharp = UIGraphicsImageRenderer(size: CGSize(width: 1700, height: 2200)).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 1700, height: 2200))
            for row in 0..<40 {
                ("\(row + 1). Factor completely: x² + \(row + 3)x + \(row * 2 + 2) and solve 3(y − \(row)) = 12" as NSString)
                    .draw(at: CGPoint(x: 120, y: 120 + row * 50), withAttributes: [.font: UIFont.systemFont(ofSize: 30)])
            }
        }.cgImage!
        let ci = CIImage(cgImage: sharp)
        let blurredCI = ci.clampedToExtent().applyingGaussianBlur(sigma: 5).cropped(to: ci.extent)
        let blurred = CIContext().createCGImage(blurredCI, from: blurredCI.extent)!
        XCTAssertEqual(ScanQuality.check(sharp), [], "\(ScanQuality.measure(sharp))")
        XCTAssertEqual(ScanQuality.check(blurred), [.blurry], "\(ScanQuality.measure(blurred))")
    }
}
