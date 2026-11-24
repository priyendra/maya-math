# Maya Math — design notes

Running record of product decisions and open discussion topics. Newest decisions at the bottom of each list.

## Principles
- Kids own their learning: no parent area, no PIN, second-person wording.
- Policies must generalize across math books. Never key behavior off one book's labels or section names
  ("Oral", "Mixed Review", "Chapter Test", …); judge by content.
- Keep the student in flow: never make her wait on Claude.
- Store data that lets us evaluate and improve the app.

## Decisions
- **Everything uploaded is fair game for practice.** Questions reviewing earlier material are included; the
  mastery model spends little time on what she already knows. The only filter is the scope she picks.
- **Exam mode** draws a mix across in-scope concepts, preferring questions not seen recently. It does not depend
  on the book having tests/quizzes (no reserving "assessment" questions).
- **Workflow:** upload scans → Claude reads pages into a clean digital chapter and tags questions in the same
  pass → one whole-chapter pass assigns concepts + difficulty → ready to practice. No pre-solving.
- **Question tags:** section hierarchy (as deep as the book goes; primary way to set scope), concept,
  difficulty 1–3, pencil-compatible (no → excluded automatically, shown greyed out in the Read view).
- **Exercise parts** that share one stem (a, b, c…) stay together as one question; graded once.
  "Oral" vs. written is ignored.
- **No separate solving step** (supersedes "just-in-time solving"). The grader solves each question itself
  first: its own answer is the first field of the grading output, before the verdict, and if it differs from her
  answer it must explain the equivalence before marking her correct. It writes a worked solution when she's
  wrong. The book's answer key, when present, goes into the grading request. Safeguards: the existing high-effort
  recheck for uncertain grades, and periodic audits of stored attempts (incl. math-library checks); bring back
  a separate solve if audits show false "correct" verdicts.
- **Generated questions get extra validation:** an independent check when a question is created, and
  stricter grading for attempts on generated questions.
- **No page dewarping.** Text is re-typeset; only diagram crops use the scan, and distortion there is minor.
- **Background grading:** "Next" moves on immediately; each answer is graded as soon as it's submitted (not
  batched); results shown at a check-in about every 10 minutes; a conceptual mistake is shown at the next
  question boundary instead of waiting. The planner uses results as they arrive.
- **Improvement data:** keep ink, rendered work, verdicts, grader logs, her corrections; add per-Claude-call
  records (kind, prompt version, model, latency, tokens/cost), raw page-reading output, app version.
  Readable over the cable; add "Export data" for other iPads.
- **Challenge questions get their own tag.** Claude tags a question as challenge when the book itself marks it
  as beyond the standard material (heading, label, symbol — judged from the page, no fixed word list); no signal
  means no tag. Rules: in practice only as occasional stretch questions after the hard level of that concept is
  mastered, and a wrong answer doesn't lower mastery or score; never in exams.
- **Pencil rule:** Claude asks "can a student answer this completely by writing with a pencil, using only what's
  on the page?" Excluded: programming, measuring/constructions with physical tools, physical models, partner or
  group activities, data collection, outside sources. Kept: graphs, sketches, tables, diagrams in the book,
  written explanations, multiple choice, and questions referring to other exercises (the referenced material is
  attached). **Calculator use never excludes a question**; the student decides whether to use one. Excluded
  questions are shown greyed out in the Read view, with an Include anyway / Exclude toggle per question.
- **Question labels:** internal IDs + the digital chapter's section tree drive everything (scope, answer-key
  linking, "show in chapter"). Claude links answer-key entries to questions directly while reading. The book's
  printed exercise number is kept as display text only (finding it in the physical book; future "paste the
  homework assignment" scopes); no logic parses it.
- **Page numbers:** a separate dimension from the section tree. Claude records each page's printed number;
  missing ones are inferred from neighbours (falls back to scan order if the book has none). After processing,
  the app reports gaps or repeats in the sequence so missing pages can be rescanned. Scopes can be set by page
  range. (First chapter: pages 185–245, complete; ~9 footers clipped by the scanner but inferable.)
- **Organization:** free-form folders (contain chapters, scopes, other folders; rename/rearrange anytime; nothing
  required). Chapters own pages, the digital version, questions and all history (attempts, mastery, mistakes).
  Scopes are saved selections of chapters/sections/subsections/page ranges, possibly across chapters, with a name
  and optional test date ("12 days to go"). Practice/exam always run inside a scope; each chapter has a built-in
  whole-chapter scope. Overlapping scopes share the chapters' mastery. Same topic in two chapters = two skills
  for now.
- **Deferred:** two students practicing the same chapter on one iPad (histories would mix). Possible fix later:
  "Duplicate chapter" without reprocessing.

- **Check-ins (background grading):** at the first question boundary after every 10 minutes of practice and at
  session end; skipped if nothing new is graded; still-grading answers roll over. Shows a one-line summary
  (done / right / faster than target), mistakes first and expanded (question, her work, where it went wrong,
  tip; solution behind "Show solution"), correct ones as a compact row, "Disagree with the grade?" on each, and
  "Keep going" (similar questions already queued for misses). Conceptual mistakes interrupt at the next
  question boundary with the same expanded view. Check-in time counts toward the session but not toward any
  question's time. Exam mode unchanged.
- **Deferred (watch in real use):** also interrupt when the *same kind* of mistake repeats on a skill (e.g.
  taking √(9a²) as 9a twice, graded "procedural" both times), since mistake categories are a judgment call.
  Revisit if real sessions show repeated mistakes slipping through to check-ins.

- **Tutor: one grounded capability, two uses.** A tutor that talks about something specific on screen: a
  solution (first) and, later, a lesson section. Built once (conversation, voice, narrated "board"), used by both.
- **Tutor input: voice or Pencil only, no typing.** Math is written with the Pencil (sent as an image) so speech
  recognition never has to parse math; speech is for everything else.
- **Solution page is composite:** the question, her work, why it was wrong (if it was), the correct solution, and
  "Talk to the tutor". Used everywhere a solution is shown (check-ins, answer details, "I'm stuck").
- **Tutor scope:** confined to the question, but broad within it: explain the underlying concept, pull relevant
  worked examples from the book, or work through a different example. Off-topic requests are steered back.
- **Voice mode is all voice:** once she enters it, the tutor speaks and listens (on-device iPad speech, a
  high-quality built-in female voice). Anything mathematical the tutor says is also written on the board.
  **Update:** built-in voices (even Ava Premium) sounded noticeably unclear; Siri's voices aren't
  available to apps. The tutor now uses **OpenAI TTS (gpt-4o-mini-tts, voice "coral" by default)** when an OpenAI
  key is saved (Settings → Tutor voice), prefetching each sentence while the previous one plays, and falling back
  to the iPad voice on any failure. The user preferred it clearly over the system voices. Interrupt = tap the page
  (no voice barge-in: the mic is off while speaking; echo cancellation would degrade playback).
- **Teaching mode is opt-in** ("Learn this section"); never required before practice or exams (she may have
  learned it in class).
- **Lessons (built):** "Lessons" on the chapter page is a table of lessons (not the book's TOC). A lesson = one
  logical unit of the book (normally a numbered section), taught in parts (an idea + its worked examples; e.g. a
  LEARN block), each ending with a "your turn" problem from the book. Claude plans the lessons once per chapter
  (outline + what each section contains); code guarantees coverage: every section with explanation/examples is in
  a part or in a visible "Not in lessons" list with a reason (enrichment, openers, reviews/tests); left-out ones
  join the nearest earlier part, or become their own lesson if their whole unit was missed.
- **Lesson scripts are written per part when she reaches it** (next part prepared while she listens), then saved:
  page items (the book's content, worked examples split into pointable steps, figures) + SAY/WRITE/POINT
  narration + 1–2 your-turn picks. Playback is local; questions go live (tap/speak any time → the tutor answers on
  the same page → CONTINUE resumes the script). "Any questions?" pause before each your-turn ("go on" handled on
  the device). Your-turn answers are graded like practice (mode lesson, count toward mastery); wrong → the tutor
  goes over it, then one more problem; then move on. Resumable by part. "Practice this lesson" after.
- **Read the chapter stays** alongside Lessons (for looking things up).
- **Pointer (proposed):** a mouse-style cursor that glides to what the voice is talking about, plus a soft
  highlight on the target, synced to the spoken words.
- **Cost:** not a constraint for now; build the good experience first.
- **The solution page is one canvas:** she can write anywhere (circle a step of her work, underline part of the
  solution). Each voice turn sends her words + a snapshot of what she's looking at with her ink (strokes new since
  her last turn tinted in the snapshot only) + the page's text/math. The page only grows downward (tutor content
  appended at the bottom) so her ink stays anchored; the tutor's cursor points into the same page. She clears ink
  herself. Conversations (words, ink snapshots, tutor replies) are saved with the answer.

- **Voice turn-taking is hands-free:** after the tutor speaks it listens; ~1.5 s of silence ends her turn (pencil
  activity keeps the turn open); tapping the page stops the tutor and listens. Gives up after ~45 s of quiet
  ("Tap Talk"). Recognition on-device when available.
- **Tutor v1 (built):** replies are tagged lines (SAY / WRITE / POINT) acted on while streaming; pointing is per
  page part (question, her work, where it went wrong, each solution step, each board line); term-level pointing
  later if needed. Context: question, her work, grading, page parts, and the textbook lesson the question belongs
  to (nearest section with its own explanation/examples). Effort low for quick replies.

- **Scan check (kids scan their own chapters):** (1) instant on-iPad check per page while scanning: blur, too dark,
  not a book page (calibrated on real scans; cut-off text is left to Claude, the on-device check was noisy), with
  Retake on the page; (2) Claude reports pages whose content is lost (cut off, blurry, covered, glare, not this
  book) while reading; with page-number gaps/duplicates this gives one kid-friendly "Rescan these pages" list.
  A new chapter waits there (before organizing) until she fixes them or taps Continue anyway. Pages scanned out of
  order are put in book order by printed page number.

- **Deferred: one coherent visual design pass over the whole app** (type scale, spacing, buttons) rather than
  enlarging individual screens (a bigger library list looked out of proportion with the rest).

- **Deferred: nicer figures in the digital chapter.** Text is transcribed well; figures are raw photo crops (grey
  paper, shadows, tilt, loose crops with stray/duplicated prose, plus a typed "(Bar model: …)" description shown
  under the picture). Found on "Rates and Speed" (46 of 363 blocks have crops). Options when we revisit:
  (1) clean-up — whiten/flatten lighting, ask Claude for tighter figure boxes (local heuristics for trimming stray
  text were fragile on tilted photos), hide the typed description when the picture shows (keep it for tutor/grading),
  skip the photo when the text already covers it; (2) redraw structured diagrams (bar models, number lines, graphs)
  as SVG with a compare-to-original check, keeping real illustrations as cleaned photos.

## Open topics
(none)



## Lesson parts can split a long section
- Some books (e.g. one long section per lesson with several worked examples, then all exercises) gave lessons of a
  single 6-8 minute part whose "your turn" tested only one of its ideas. A part may now teach a slice of one
  section: worked examples from…to plus the explanation leading up to them (`LessonPart.fromExample/toExample`).
- The planner sees each multi-example section's examples (numbered, first line) and is told to split where the idea
  changes, aiming for 3-6 minute parts; sections that already teach one idea (e.g. LEARN/TRY boxes) are not split.
  Validation makes split ranges contiguous and complete; exercise sections can serve every part of their lesson.
- "your turn" must practise the part's own idea. Book-agnostic: nothing depends on a particular textbook.
- Older plans with a part covering ≥3 worked examples, and no lesson started, are replanned once automatically.
- Part scripts with fewer than 3 spoken lines are never saved (retry, then "Try again"); bad saved ones are rewritten.

## Visual design
- Classic design chosen (from four options tried in the app). Tokens in `Theme.classic`: one accent, and colours
  with one meaning each — learn (blue), done/correct (green), attention (orange), not quite (soft rose, never harsh
  red), board (indigo); one type scale. Applied to library, chapter page, lessons, lesson page, practice, check-ins,
  solution page, exam intro, My answers, My progress. App icon: white radical + gold spark on blue→indigo
  (`tools/make-app-icon.swift`).

## Skills grid and summary bar
- The mastery rule is unchanged (the user wants the bar as is). Only how it's shown changed: a percentage read as
  "fraction done/right", so cells show **5 dots = steps toward the star** (dots = how many right-in-a-row answers the
  score is worth: 30/51/66/76/83%) plus a **named stage** by colour: Not started (light blue, empty dots), Learning (rose, <30%), Getting there
  (orange, <60%), Almost (yellow, ≥60%, which also unlocks the next level), Mastered (green ★). A timer means "right
  enough for the star, now a bit faster". A level that re-locks after the level below slips keeps its dots, greyed.
- Legend under the grid and a "How this works" popover in second person.
- Summary bar above the grid (chapter page, study plan, My progress): answered (+today), % right (+today), practice
  time and days, mastered of total cells + how many are Almost, review due (only once something is mastered), days to
  the test (when a date is set), and "N answers to check".
- Next: tap a cell for details (step 2), then an "analyze my work" feedback feature (step 3; recent vs all history
  still to discuss).
- The "Up next" lesson card was removed from the chapter page; the next lesson is reached from Lessons
  (which marks it "Up next" / "In progress").

## Progress summary and mastery points
- **Mastery points (0–100)** are the chapter's (or study plan's) one number. Each skill level (concept × Basic/Medium/
  Hard) earns up to 100 as its score climbs to star level (80%); points = the average, untried or locked levels = 0.
  So 100 = every level at star level, for any book. Not a percentage (kids read % as "fraction right").
  Points can drop after wrong answers.
- **Chapter page "Progress summary"**: points as the headline with "+N today" (vs the end of yesterday), a line chart of
  points over **practice time** (x = cumulative active time, a point every 30 min, rebuilt by replaying answers; no
  dots or grid, bold line, dashed "★ 100" goal line), and one line: answered · % right · practice time · answers to
  check. Removed from the chapter page: the full grid, the small map, "Focus next", "See all" (the My progress tile
  goes there). Clock time / test date on the axis was tried and dropped.
- **My progress (interim, under discussion next)**: one path per skill (Basic → Medium → Hard → ★, 5 steps per level;
  mastered = top level mastered) with the summary tiles. Known issues: passed levels show full though only ~3 steps
  were earned; a level that re-locked isn't shown; "Per concept" still below.
- Known: the chart's time axis counts only answers that moved a score, so it ends slightly short of total practice time.
- Math is rendered everywhere Claude's text can contain it: answers on the answer page and the book
  answer use KaTeX (`MathRow`); short labels (chapter/section/skill names, lesson summaries, tutor captions) use
  Unicode via `MathPlain`. **"Grade it again"** on an answer Claude wasn't sure about re-runs grading; the earlier
  grading log is kept below the new one, and a question the first grading retired as flawed comes back if the new
  grading finds it fine. Verdicts read "Correct / Not quite / Not sure — to check".

## Teacher's feedback
- A card below Progress summary on the chapter page: Claude's notes to the student — a bold one-line headline,
  then **What's going well / The one habit to fix / Where to practise next**, quoting her own mistakes. Shown in
  full (no fold): the chapter page has the room, and the specific examples are the useful part.
- Written first after 10 answers, then after every **30 minutes of practice time** (active seconds on answers, as
  in the chart), not clock time. Stored on the chapter (`feedbackHeadline/Text/AtSeconds/Date`).
- Input (`FeedbackSummary`): recent work = her last hour of practice, in full (counts per skill level + the
  grader's "where it went wrong" for every mistake); earlier work in brief (counts + latest 12 mistakes). The prompt
  weighs recent work most but uses earlier work for context (praise a fixed habit, flag a recurring one). The app
  computes every number; Claude only writes.
- The card is hidden until there are 10 graded answers (or earlier feedback exists). Study plans get
  their own Teacher's feedback (below the skills panel), stored on the plan. "Practice time" is one definition
  everywhere — every answer's active time: the chart's time axis, the line below it, and the feedback timer. Answers
  that don't move the score (waiting, to check, challenge, hinted) still add time to the chart.
- UI tests launch with `-freshStore` (DEBUG only): the app deletes its store and settings at launch, so no test
  depends on data another test or a real-data screenshot run left behind.

## My progress and the answers browser
- My progress: a skills × levels grid (Basic / Medium / Hard). Each cell is a bar of that level's mastery points
  (0–100), coloured by value (red → amber → yellow-green; green with ★ once mastered). A lock shows only on levels
  she has never answered (a level reached through stretch practice is never shown locked). Below: Mistake types.
  "Per concept" and the stat tiles were removed (the chapter page has the totals). Stars were tried and dropped:
  levels often sit around 82, and a star filled to 82% looks full.
- One answers browser everywhere (My answers, a skill's page, a mistake type's page), with the same filters —
  skill, level, mistake type, newest/oldest first — and the same card: one card per question with all her answers
  (grade, date, time, handwriting, the grader's "where it went wrong"). Pages differ only in starting filters and
  header (skill: points + what each level needs; mistake: one-line meaning; My answers: To check / still being
  checked pinned on top).
- Every card has "See in chapter": opens Read chapter at the exercise's section, scrolled to it and highlighted. A
  generated question links to the book exercise it was made from.
- Answer lists use native text with Unicode math (`MathPlainText`), never web views: one web view per
  math block made scrolling stutter, half-drew text, and (lazily rebuilt at a placeholder height) made the page jump in
  a loop. Full KaTeX stays on single-item pages (answer page, solution, lessons). `MathText` also remembers measured
  heights so rebuilt views don't resize. Unicode math spaces relations and top-level +/− ("3𝑥² − 41𝑥 = −60").
- One filter row: Answers menu (All / Correct / Wrong answers, then each kind of mistake), Skill menu, Level menu,
  count, newest/oldest toggle. 25 cards at a time with "Show more".
- Tappable rows look tappable: whole-row buttons that highlight when pressed, ending in a blue › in a
  circle (skills grid, mistake types). Filter pills are 44 pt tall chips; an active filter is filled blue. The
  Answers menu groups "Mistake categories". "See in chapter" is also on the answer page and the solution page.
- The answer page offers only the other grade: a correct answer can be marked wrong (choosing its kind of
  mistake), a wrong one marked correct. Mistake types never show on correct answers (also not to the lesson tutor).
- Study plan pages match chapter pages: Practice / Exam, then tiles (My answers, My progress, Edit
  study plan), the Progress summary card (mastery points chart + practice line) and Teacher's feedback. My progress
  works for any study set; a plan shows the exams taken mostly on its own questions. The session summary shows the
  skill bars (not tappable). The old coloured grid, its stages/legend/help, the path views and their summaries are gone.
- Mastery is accuracy only: a level is mastered at 100 mastery points (score 0.8, about 5 right in a row). No star,
  no speed condition: time never raises or lowers mastery. Practice still records each answer's time (her baseline
  pace per skill level), but shows no per-question clock or targets. Time pressure belongs to exam mode only.
- Exam mode has three independent settings, picked by the student on the exam's start screen (remembered):
  **How hard** Normal (Basic/Medium/Hard in even parts) · Hard (Medium + Hard) · Hardest (mostly Hard);
  **How fast** Normal · Fast · Fastest = her own practice time per question ÷ 1, 1.25, 1.5;
  **How long** 20 · 30 · 45 min = the time limit. The exam holds as many questions as fit in that time at that pace.
  "Her own time" = question estimate × her typical (median) time ÷ estimate on right practice answers for that skill
  level (≥3), else for that level, else the estimate. The app never suggests a setting; she decides.
  Exam length is no longer a chapter / study plan setting. "My exams" (a link on the exam start screen) lists every
  exam with its settings, score and time; tapping one shows its question-by-question results.
- The exam clock is strict wall-clock time from Start: it keeps running if she leaves the app, is always at the top
  of every question, turns red for the last 5 minutes, and the exam hands itself in at 0 with no grace ("Time's up").
  She can move between questions and change answers until then. Answers are graded with the same grader as practice
  (any valid method), only after hand-in; nothing is shown until the results.
- Breaks are not pace: an answer's time is an outlier when log(time ÷ estimate) is more than 2 SD above her mean on
  that level AND over 3 minutes (a fixed cutoff would drop real 5-minute word problems). Outliers are left out of pace
  figures and count as her typical time in practice-time totals (chart, practice line, feedback timer); the measured
  time is still stored.
- Teacher's feedback includes **Your pace** as a key section: pace vs estimates per level, recent vs earlier, right
  vs wrong answers (slow-but-right = needs fluency; wrong much faster than right = rushing), slowest skill levels.
- Drafts survive the app closing (files under Application Support/Drafts, one per practice set / exam):
  practice saves the current question's ink and time every few seconds and when the app goes to the background, and
  restores it when practice reopens on that chapter or plan (if recent and still unanswered); an exam saves every
  answer when she moves between questions, every few seconds and on background. Reopening Exam mode returns to a
  running exam (its clock kept running); if its time ran out meanwhile, it hands in what she wrote.
- The practice question shows the book place ("Ex. 12 · p. 236"); tapping it opens the chapter at that exercise.
  Clocks stop while she reads; Back returns to the question. Exams have no such link. Looking at the book counts as
  a hint (she is told before it opens, once per question): the answer doesn't move mastery, the check-in says so.
- Waiting for grading shows progress: "x of y checked" with a bar (end of practice and after an exam).
- The screen tour UI test is opt-in (TEST_RUNNER_TOUR=1). Bundled KaTeX and marked licences: THIRD_PARTY_NOTICES.md.
