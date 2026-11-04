# AI Bootstrap User Manual: Keeping Project Documentation Up to Date

## Contents

- [How It Works](#how-it-works)
- [When to Update](#when-to-update)
- [How to Update](#how-to-update)
- [Manually Editing PROJECT_OVERVIEW.md](#manually-editing-project_overviewmd)
- [Avoid Duplicating Project Knowledge in Tool-Specific Files](#avoid-duplicating-project-knowledge-in-tool-specific-files)
- [Model Requirements](#model-requirements)

## How It Works

AI Bootstrapping generates `PROJECT_OVERVIEW.md` and `AGENTS.md` for each managed repository. These files give AI coding agents instant context about the project — architecture, tech stack, conventions, and gotchas — so they can start working productively without lengthy exploration.

`PROJECT_OVERVIEW.md` holds the comprehensive project documentation. `AGENTS.md` acts as the standardized entry point: it contains a single instruction to read `PROJECT_OVERVIEW.md` and is natively picked up by tools like Cursor and GitHub Copilot.

Each generated file is read *in addition* to whatever tool-specific configuration may already exist (e.g., `.github/copilot-instructions.md`, `.cursorrules`). There is no conflict — it just ensures every tool gets pointed to the same shared knowledge base.

## When to Update

Re-run the bootstrap process after significant changes to a repository, such as:

- New modules, services, or major dependencies added
- Build system or CI/CD pipeline changes
- Infrastructure or deployment changes (new environments, database switches)
- Major refactoring that changes the project structure

A good rule of thumb: if the change would surprise an AI agent relying on the current `PROJECT_OVERVIEW.md`, it's time to re-bootstrap.

## How to Update

1. From the AISENGARD checkout, start a bootstrap session with the target repository's configured catalog path or full HTTPS GitHub URL:

   ```bash
   ./aisengard_cli/aisengard init bootstrap <owner/repository-or-url>
   ```

2. Follow the structured instructions returned by the CLI in an AI coding agent session.

3. During the process you may encounter prompts that require your attention:

   - **Rate-limit warning:** The agent performs many operations in quick succession, which can trigger a built-in rate-limit alarm (a safeguard against infinite loops). If this happens, simply press **"Continue"** to let the process resume.
   - **Temporary file deletion:** The analysis creates temporary intermediate files that are cleaned up at the end. Your tool may ask you to confirm the deletion — approve it to complete the cleanup.

4. Review the generated `PROJECT_OVERVIEW.md` and `AGENTS.md`, then review and merge the generated pull request.

## Manually Editing PROJECT_OVERVIEW.md

Minor inaccuracies — such as outdated version numbers or a renamed CLI flag — can be corrected directly in `PROJECT_OVERVIEW.md`. These small touch-ups are normal and expected.

However, if you spot **clear errors or gaps in understanding** (e.g., a misrepresented data flow, a missing module, or wrong architectural assumptions), **do not just fix the generated file**. Instead, improve the project's own documentation so that the next bootstrap run produces a correct result on its own. The bootstrap process derives its understanding entirely from the code and the existing docs. If the AI gets something fundamentally wrong, that is a clear signal that the necessary documentation is missing or insufficient — not that `PROJECT_OVERVIEW.md` needs a manual patch.

**Rule of thumb:** Ask yourself *"Could the AI have gotten this right with better input?"*

- **Yes** → Add or improve the relevant project docs (READMEs, architecture notes, inline comments), then re-bootstrap.
- **No, it's just a small detail** → Edit `PROJECT_OVERVIEW.md` directly and move on.

## Avoid Duplicating Project Knowledge in Tool-Specific Files

The real risk is **redundancy**: project information (architecture, conventions, tech stack, etc.) maintained both in tool-specific configuration files *and* in `PROJECT_OVERVIEW.md`. Over time these copies drift apart, leading to contradictions.

Maintaining project knowledge exclusively in tool-specific files is an **antipattern**. These files are tied to a single tool and invisible to developers who use a different agent — or no agent at all. `AGENTS.md` (and `PROJECT_OVERVIEW.md`) are the better place for such information because they are:

- **Tool-agnostic** — every AI coding agent can consume them.
- **Human-readable** — developers benefit from the same documentation regardless of tooling.
- **Single source of truth** — one place to update, one place to review.

**Guideline:** Tool-specific files should contain only *tool-specific* configuration (keybindings, model selection, permission rules, etc.). Any information that describes the *project itself* belongs in `AGENTS.md` or `PROJECT_OVERVIEW.md`.

## Model Requirements

The bootstrap process involves deep codebase analysis across multiple phases and produces structured documentation that AI agents will rely on. **Always use a high-end model with maximum thinking/reasoning enabled** to ensure the best possible result.

Recommended models:

- **Claude Opus** (with extended thinking at maximum budget)
- **GPT Codex** (or the latest flagship OpenAI model)

Do not use smaller or faster models (e.g., Haiku, GPT-4o mini) for bootstrapping — the quality of the analysis reports and the final documentation depends heavily on the model's reasoning capability.
