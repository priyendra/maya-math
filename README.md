# Math Practice (iPad)

Scan textbook pages into a chapter; Claude extracts, solves and categorizes the questions; the student practices
with Apple Pencil and Claude grades her handwritten work. An adaptive scheduler spends most time on weak skills,
re-practices mistakes, and pushes on speed once accuracy is solid. Exam mode gives timed mixed tests.

## Setup
1. `brew install xcodegen` (once), then `xcodegen generate` and open `MathPractice.xcodeproj`.
2. Select the MathPractice target → Signing & Capabilities → choose your Team (a free Apple ID works, but the app
   must be re-installed every 7 days; a paid developer account avoids that).
3. Connect the iPad, pick it as the run destination, press Run.
4. In the app: tap the shield (Parent) → set a PIN → paste a Claude API key from console.anthropic.com.
   Set a monthly spend limit on that key in the Console.

## Using it
- **New chapter (+)**: scan pages (or import photos / a PDF). Toggle "Answer key" on any answer pages.
  Processing takes a few minutes; it resumes if the app is closed.
- **Parent → chapter**: check the questions Claude wasn't sure about (they're held back until approved),
  fix any text/answer, review gradings, override a grade, and see the progress report.
- **Practice**: 30-minute adaptive session. **Exam mode**: timed mixed test; length set in Parent → chapter.

## Development
- `xcodebuild test -scheme MathPractice -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)'`
- Debug launch arguments: `-seedSample` (sample chapter, no API needed), `-openFirstChapter`, `-autoPractice`, `-autoExam`.
- Layout: `Claude/` (API client, prompts, schemas, chapter pipeline, variant generator), `Learning/` (mastery,
  planner, exam builder — pure Swift, unit-tested), `Views/`, `Support/` (KaTeX math rendering, scanner, Keychain).
