# Agent portability

Keep the complete `deploy-comfyui-amd-windows` directory together. The workflow depends on relative links among `SKILL.md`, `scripts/`, `references/`, and `assets/`; it does not depend on Codex-specific tool names or APIs.

## Agents with SKILL.md support

Copy the whole directory into that agent's documented project-level or user-level skills directory. Restart/reload the agent if its skill discovery runs only at startup. Confirm that the agent displays the skill name and description before asking it to deploy.

Cline, for example, documents project skills under `.cline/skills/` and user skills under `%USERPROFILE%\.cline\skills\` on Windows. Its Skills feature may need to be enabled. Re-check the current product documentation before copying because discovery paths can change: <https://docs.cline.bot/customization/skills>

## Agents without native skills

Place the directory inside the project, then instruct the agent to read `SKILL.md` fully and follow it as the governing deployment procedure. The agent must be able to run PowerShell, read JSON, browse current official compatibility documentation, and request user approval for privileged actions. If it cannot do one of those, it should stop at the affected gate and hand the user the exact command instead of pretending to complete it.

## Security boundary

Do not grant an agent unrestricted permanent access merely to use this skill. Approve narrowly scoped package downloads, process launches, and writes to the chosen install/desktop paths. The scripts themselves do not disable security products, change global execution policy, install drivers, or overwrite a non-empty deployment root.
