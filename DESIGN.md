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

## Open topics (discuss in order)
1. Background grading details: check-in interval, what the check-in screen shows.
