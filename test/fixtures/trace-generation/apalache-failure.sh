#!/usr/bin/env bash
set -eu
printf 'synthetic stdout: run=%s unicode=测试\n' "$PWD"
printf 'synthetic stderr: category=typecheck detail=' >&2
printf '%012000d' 0 >&2
printf '\n' >&2
exit 42
