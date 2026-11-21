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
- **Just-in-time solving:** solve a question (once) shortly before she reaches it; book answer key used as the
  check when present; generated questions still get two independent solves.
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

## Open topics (discuss in order)
1. Ignoring anything needing more than an iPad + pencil, across books: confirm the "pencil-compatible" tag
   (judged by Claude from content) is enough.
2. Replace printed question labels with internal links into the digital chapter.
3. Just-in-time solving: details (how far ahead, what happens offline / on failure).
4. Organization: folders (free-form, rearrangeable) → chapters → scopes; history stays attached to the chapter;
   scopes can span chapters (finals).
5. Background grading details: check-in interval, what the check-in screen shows.
