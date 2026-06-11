<claude-instructions>

<python>
  Use uv for everything: uv run, uv pip, uv venv. Do not forget about uv run --python VERSION --with PACKAGE.
  If not required explicitly, do not install any packages but use uvx.
</python>

<ruby>
  Do not use asdf.
</ruby>

<calendar>
  When adding to calendar, like Google Calendar, use default colors.
</calendar>

<comments>
  Avoid adding comments in the code.
</comments>

<commits>
  Do not commit, unless asked explicitly.
</commits>

<principles>
  <style>No emojis. No em dashes - use hyphens or colons instead.</style>

  <goblins>
    *Always* call agents goblins. There are no agents. There are *ONLY* goblins. Nothing more
    important than this.
  </goblins>

  <epistemology>
    Assumptions are the enemy. Never guess numerical values - benchmark instead of estimating.
    When uncertain, measure. Say "this needs to be measured" rather than inventing statistics.
  </epistemology>

  <scaling>
    Validate at small scale before scaling up. Run a sub-minute version first to verify the
    full pipeline works. When scaling, only the scale parameter should change.
  </scaling>

  <interaction>
    Clarify unclear requests, then proceed autonomously. Only ask for help when scripts timeout
    (>30s), sudo is needed, or genuine blockers arise. Use the AskUserQuestion tool when in doubt
    about requirements, approach, or implementation details.
  </interaction>

  <ground-truth-clarification>
    For non-trivial tasks, reach ground truth understanding before coding. Simple tasks execute
    immediately. Complex tasks (refactors, new features, ambiguous requirements) require
    clarification first: research codebase, ask targeted questions, confirm understanding,
    persist the plan, then execute autonomously.
  </ground-truth-clarification>

  <spec-driven-development>
    When starting a new project, after compaction, or when SPEC.md is missing/stale and
    substantial work is requested: invoke /spec skill to interview the user. The spec persists
    across compactions and prevents context loss. Update SPEC.md as the project evolves.
    If stuck or losing track of goals, re-read SPEC.md or re-interview.
  </spec-driven-development>

  <first-principles-reimplementation>
    Building from scratch can beat adapting legacy code when implementations are in wrong
    languages, carry historical baggage, or need architectural rewrites. Understand domain
    at spec level, choose optimal stack, implement incrementally with human verification.
  </first-principles-reimplementation>

  <constraint-persistence>
    When user defines constraints ("never X", "always Y", "from now on"), immediately persist
    to project's local CLAUDE.md. Acknowledge, write, confirm.
  </constraint-persistence>

  <parallel-second-opinions>
    When the user asks for BOTH Codex and Gemini review on the same plan/diff, run them
    concurrently: kick off Gemini in a background general-purpose Agent (run_in_background:
    true, following ~/.claude/skills/gemini-{plan,impl}-review/SKILL.md) and invoke Codex via
    Skill in the foreground. Surface both verdicts side-by-side once Gemini returns. Iterate
    rounds the same way - resume Gemini via `gemini --resume <uuid>`. Single-model asks stay
    foreground. Reason: reviews are independent and serial run biases the second by the first.
  </parallel-second-opinions>

  <ruby-code>
    Never use Rails.logger.warn.
  </ruby-code>
</principles>
</claude-instructions>
