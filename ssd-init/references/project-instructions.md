# Shared project instructions

Install this block only with consent, inside `<!-- ssd:managed id=project-instructions -->`.
It is the block a user's project receives. It is not this repository's contributor guide.

## SSD

Work follows brief, design, code, review, gate, then a human ship. Bare `/ssd` reads state and proposes the next action. It does not implement and it does not start Feynman, software-standards, or codebase-skeptic.

The human supplies the objective and the acceptance criteria. Do not change them so a check will pass. Do not ship, deploy, publish, or remove a release control unless the user explicitly invokes that step. There is no `--force`.

Executable checks live in the installed SSD library: `methodology/gate-rules.sh` and `methodology/autorun.sh`. Resolve the library root; do not search the project for a copy that is not there. A missing `.ssd/` means propose `/ssd-init`. A state file that does not parse is corrupt, not an empty project.

A gate result names the snapshot it checked. `PASS`, `FAIL`, `ERROR`, and `NOT_RUN` are different. Missing tools are not success.
