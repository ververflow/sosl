# SOSL Domain Config: Bundle Size
# Build output is deterministic — no noise floor needed beyond default
# Only frontend files may be modified
ALLOWED_PATHS="frontend/src/*,frontend/next.config.*"
# Secondary: monitor code quality while optimizing bundle size
SECONDARY_DOMAINS="code-quality"
