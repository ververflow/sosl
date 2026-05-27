# shellcheck shell=bash
# shellcheck disable=SC2034  # vars consumed by sourcing scripts
# SOSL Domain Config: Performance
# Lighthouse scores on dev servers vary 20-30 points — high minimum noise floor
MIN_NOISE_FLOOR=3.0
# Only frontend files may be modified for performance optimization
ALLOWED_PATHS="frontend/src/*,frontend/next.config.*"
# Secondary metrics: monitor bundle size and code quality while optimizing performance
SECONDARY_DOMAINS="bundle-size,code-quality"
