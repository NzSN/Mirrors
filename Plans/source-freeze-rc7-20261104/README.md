# Recovered-source rc.7 freeze — 2026-11-04

Status: the user-authorized full local non-model gate passed after published
recovery `d541d242d977308ddc1b7fe6c92b75eb0548b3ef`. Source and companion
identities stayed stable throughout the 140-second run. Clean task-owned source
and fresh C0/snapshot construction are executing; final acceptance awaits
independent verification.

This stage prepares `0.2.0-rc.7`, preserving all earlier refs and package bytes.
The committed vendor carrier remains `f6efbfeb…`, 3,684,180 bytes, at unchanged
Batteries source `4488d40d…` / tree `5a1de86f…`. The selected execution scope is
Ubuntu 26.04.1 WSL2; base Ubuntu 24.04 remains a structural control.

Raw execution evidence and task-owned source/candidate/snapshot outputs are
retained under ignored owner-only `.golden-build/source-freeze-rc7-20261104/`.
The full gate uses that root's ext4 `tmp` directory and the admitted host
context. It runs no local Apalache/TLC. Installed D, M5/Q, Windows, remote-model,
release and deployment acceptance remain separate.

Shared branch commit/push, tags, package creation, remote service changes and
deployment are not performed by this source-freeze stage. A clean task-owned
local commit may bind the reviewed source without modifying shared branch refs.
