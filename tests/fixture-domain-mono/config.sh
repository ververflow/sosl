# shellcheck shell=bash
# shellcheck disable=SC2034
# backend/* is deliberately in scope so changes there reach the stack guards
# (the scope guard would otherwise block them before layer 2).
ALLOWED_PATHS="score.txt,notes.md,backend/*"
MEASURE_TIMEOUT=10
MIN_NOISE_FLOOR=0.5
