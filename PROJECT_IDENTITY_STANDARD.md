# Project Identity Standard

Status: permanent engineering governance. This is not TPM-specific instruction
-- it is written to apply to every Jumpstile project and should be copied or
referenced, unmodified in substance, wherever a new Jumpstile project needs
the same policy.

There is no existing "Engineering Canon" or "Constitution" document in this
repository to fold this into. This file is the canonical source for identity
and attribution policy until/unless a higher-level cross-project governance
document exists, at which point this file should be replaced with a pointer
to it rather than duplicated.

---

## 1. Public project identity

Every Jumpstile public-facing software project has exactly one public
identity: **Jumpstile**. This is the name that appears as author, committer,
maintainer, and point of contact everywhere the project is visible --
commits, releases, documentation, issue/PR activity, and any packaging or
distribution artifact.

A project may have exactly one public identity at a time. If a project's
identity is ever renamed or transferred, that is a deliberate, explicit
decision recorded in the project's own history -- never an accident of tooling
or environment configuration.

## 2. Branding standard

- Project names, logos, and terminology are the project's own. No
  third-party tool, platform, or service is credited as a co-author,
  contributor, or brand presence on a public-facing artifact unless that
  tool's own license explicitly requires attribution (see Section 13).
- Release names, tags, and titles describe the software, not the process or
  tooling used to build it.

## 3. Personal identity separation

Jumpstile projects and personal/work-facing identities are kept strictly
separate:

- `Jumpstile` is the identity for Jumpstile public/personal projects.
- Any other personal or work-facing identity (e.g. an Engineering System /
  ES identity used for internal work across projects) must never appear as
  an author, committer, co-author, or named contributor on a Jumpstile
  public project surface.
- This separation exists because the two identities serve different
  purposes and different audiences; mixing them defeats the purpose of
  having separate identities at all, regardless of how the mixing happened
  (manual mistake, environment misconfiguration, or automated tooling).

## 4. AI / tool attribution policy

No commit, commit message, file, comment, documentation page, wiki page,
release title, release description, release note, changelog entry, issue,
PR title, PR description, PR comment, or packaged artifact may name or brand
a specific AI assistant, LLM product, or AI vendor. This includes but is not
limited to: Claude, Claude Code, ChatGPT, Codex, OpenAI, Anthropic, Gemini,
Copilot, Cursor, Grok, or any other AI assistant/LLM product, present or
future.

This is not a statement that AI assistance is not used -- it is a branding
and identity-separation rule, not a disclosure prohibition. Internal /
private engineering notes not shipped as part of the project are outside
this policy's scope.

**Preferred neutral terminology**, to be used wherever process or review
needs to be described:

- "independent engineering review"
- "engineering review"
- "implementation review"
- "architecture review"
- "engineering analysis"
- "regression testing"
- "release-hardening review"
- "independent verification"

The goal is always to describe *what happened* (a review found blockers, a
regression suite was run) rather than *what tool performed it*.

### GitHub UI attribution (Apps/connectors)

Comments created through a GitHub App or connector (e.g. a ChatGPT/Codex
GitHub connector) can carry GitHub's own UI-level attribution -- something
like "with ChatGPT Codex Connector" rendered by GitHub itself alongside the
comment. This is not part of the comment body, is not authored/editable
text, and cannot be removed by editing the comment.

- Do not treat GitHub's own UI-level attribution as a violation of this
  policy. This policy governs text inside comment bodies, PR bodies,
  commit messages, documentation, and generated files (the opening list
  above) -- not chrome GitHub itself renders around a comment.
- The ban on attribution text *inside* comment bodies, PR bodies, commit
  messages, docs, and generated files is unaffected and still applies in
  full. This carve-out is only for GitHub's own immutable UI chrome, never
  for anything an author actually writes into the content itself.
- Official, polished, public-facing reviewer comments -- the kind meant to
  stand as the durable record of a review outcome -- should be posted
  through the designated reviewer path, i.e. whichever posting path does
  not attach unwanted connector UI attribution, so the public issue/PR
  history reads as clean project engineering communication.
- A ChatGPT/Codex connector-posted comment is acceptable for internal
  coordination or a low-risk, working-notes-style review comment, where the
  UI attribution is a minor cosmetic artifact. It should not be the
  preferred path when clean presentation of official public-facing issue
  history matters -- use the designated reviewer path for those instead.

## 5. Commit identity policy

- Author and committer on every commit reaching a public branch must be
  `Jumpstile <29765787+Jumpstile@users.noreply.github.com>`.
- No `Co-authored-by:` trailer may name a personal identity other than
  Jumpstile, or any AI tool.
- Before committing in a Jumpstile project's working copy, verify
  `git config user.name` and `git config user.email` resolve to the
  Jumpstile identity above. Do not assume an inherited global config is
  correct -- confirm it for this repository, every session.
- If a commit is ever found with the wrong identity before it reaches a
  public branch, fix it before pushing. If it is found after reaching a
  public branch, treat it as a Section 12 compliance gap and remediate per
  that section's guidance on rewrite risk vs. benefit.
- Each project should provide a tracked prevention guard, not rely on
  memory alone. TeknoParrot Manager's is `.githooks/pre-commit`; enable it
  once per clone with `git config core.hooksPath .githooks`. A new
  Jumpstile project should carry the same hook, adjusted only for its own
  expected identity if it differs from the one in Section 1.

## 6. PR identity policy

- PR author, title, description, and comments must not name a personal
  identity other than Jumpstile or any AI tool.
- A PR opened by an external contributor or automated agent under a
  different identity is a real, distinct case (not a violation to silently
  rewrite) -- but before merge, any squash/merge commit produced from it
  must not carry that identity or an AI-tool mention into the resulting
  public history (see Section 8; GitHub's squash-merge auto-generates
  `Co-authored-by:` trailers from the source commits' authors, which must be
  stripped or avoided).

## 7. Release identity policy

- GitHub Release titles, tags, and descriptions name the project and the
  version, never a tool, reviewer identity, or process detail that isn't
  relevant to what the software does.
- Release notes may describe engineering process in neutral terms (Section
  4) but never name specific AI tools or a non-Jumpstile personal identity.

## 8. Wiki identity policy

- The wiki is a separate git repository with its own history and is
  subject to the same commit identity policy as Section 5.
- Wiki page content is subject to the same branding and attribution
  policy as Section 4.
- Because the wiki is lower-visibility than the main repository, it is
  not lower-priority -- a compliance sweep must explicitly include it, not
  assume it inherits cleanliness from the main repo.

## 9. Documentation identity policy

- README, QUICKSTART, CHANGELOG, and any other tracked documentation file
  must not name a non-Jumpstile personal identity or a specific AI tool.
- Internal engineering documents that stay out of the release ZIP (e.g.
  architecture notes, lessons-learned logs) may describe engineering
  process in more detail, but still may not brand a specific AI tool or
  personal identity per Section 4 -- the exemption is for detail, not for
  the branding rule itself.

## 10. Release note policy

Release notes describing a hardening or review pass use the neutral
terminology in Section 4. They describe what was verified and what changed,
not who or what tool verified it.

## 11. Verification gates

Before any release is tagged or any content is published, verify:

- `git log --all --format='%an|%ae|%cn|%ce'` across every public branch and
  tag returns only the Jumpstile identity.
- No `Co-authored-by:` trailer names anyone but Jumpstile.
- A full-text search (commit messages, tracked file content, wiki content,
  issue/PR text where editable, release descriptions) for personal-identity
  and AI-tool terms returns no matches outside of legitimate exceptions
  (Section 13) or the terms' own definitional appearance in a policy/test
  file like this one or `Tests/NoAIAttribution.Tests.ps1`.
- Wiki history and content are included in the sweep, not assumed clean.

## 12. Compliance checklist

Use this checklist for any identity/attribution audit or cleanup pass:

- [ ] `git config user.name` / `user.email` verified correct before any commit.
- [ ] All public branches' commit authors/committers are Jumpstile only.
- [ ] No `Co-authored-by:` trailers name a non-Jumpstile identity.
- [ ] No tracked file, commit message, issue, PR, release, or wiki page
      names a personal identity other than Jumpstile.
- [ ] No tracked file, commit message, issue, PR, release, or wiki page
      names a specific AI tool/vendor (Section 4 list), except this policy
      document and `Tests/NoAIAttribution.Tests.ps1` themselves.
- [ ] Wiki repository history and content checked, not assumed.
- [ ] Any historical violation already on a public branch is triaged per
      Section 5's rewrite-risk guidance, and the decision (rewrite vs.
      accept-and-document) is recorded.
- [ ] A prevention mechanism (documented guard, hook, or equivalent) exists
      and is referenced from this repository's contributor-facing setup
      instructions.
- [ ] Where a proposed reference is uncertain rather than clearly required,
      the privacy-first default (Section 14) was applied or the reference
      was confirmed with the project owner before publishing.
- [ ] Any conflict found between this document and an existing artifact was
      reported, with a compliant resolution recommended, per the governance
      hierarchy (Section 15) -- not silently resolved in either direction.

## 13. Exceptions

There are two exceptions to this policy:

- A third-party license that explicitly requires attribution (e.g. an
  open-source library's license text) must be honored exactly as that
  license requires, in the location it requires (e.g. a `LICENSE` or
  `THIRD_PARTY_NOTICES` file). This is not a branding statement about the
  Jumpstile project; it is compliance with someone else's license.
- GitHub's own UI-level attribution on comments posted through a GitHub
  App/connector (see Section 4, "GitHub UI attribution") is not a policy
  violation -- it is platform chrome rendered by GitHub itself, not
  authored content, and cannot be edited away. This is listed here (rather
  than only in Section 4) because it is the other case where attribution
  can be visibly present on a public artifact without being a violation.
- No other exception exists. In particular, "it's just internal engineering
  detail" is not an exception for anything that ships as part of the public
  project (Section 9 already carves out non-shipped internal documents
  separately, on narrower grounds).

## 14. Privacy-first default

If there is any uncertainty about whether a public-facing artifact should
contain a personal identity, a work identity, an email address, an AI
assistant name, an AI product name, a development tool name, or branding
that is not Jumpstile, default to the privacy-preserving option: use
neutral engineering language (Section 4) instead. If uncertainty remains
even after choosing neutral language, stop and ask before introducing the
reference at all. This default applies everywhere this document applies --
it is not a separate, lower-priority preference.

## 15. Project governance hierarchy

When applicable, Jumpstile project governance is followed in this order:

1. `CONSTITUTION.md` / Engineering Canon (if present in a given project).
2. This document (`PROJECT_IDENTITY_STANDARD.md`).
3. Architecture Decision Records (ADRs).
4. Repository-specific engineering standards (e.g. `SECURITY.md`,
   `RELEASE-SAFETY-CHECKLIST.md`, `ARCHITECTURE.md`).
5. Task-specific instructions.

If an existing file, issue, PR, release note, wiki page, or other public
artifact conflicts with this document, this document is authoritative.
The conflict must be reported and a compliant resolution recommended before
proceeding with the task that surfaced it -- silently picking one side of
the conflict is not an acceptable resolution.

Once this document is created and integrated into a project's governance
hierarchy, it applies automatically: every significant PR, merge
recommendation, and release is audited against it without needing to be
asked each time. A believed-necessary change to the standard itself is
proposed through the normal governance process (a PR against this
document), not bypassed in the moment it's inconvenient.

---

## Applying this standard to a new Jumpstile project

1. Copy this file into the new project's repository root, unmodified in
   substance (project-specific examples may be added, but Sections 1-13
   should not be weakened).
2. Add a reference to it from the project's own governance documents
   (whatever exists: architecture notes, release checklists, contributor
   guide, security policy).
3. Set repository-local git identity explicitly at first clone, per
   Section 5.
4. Add the compliance checklist (Section 12) to the project's release
   checklist as a required gate, not an optional pass.
