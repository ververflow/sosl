# shellcheck shell=bash
# shellcheck disable=SC2034  # vars consumed by sourcing scripts
# SOSL Domain Config: Code Quality
# ESLint is deterministic — no noise floor needed beyond default
# Only frontend source files may be modified
ALLOWED_PATHS="frontend/src/*"
