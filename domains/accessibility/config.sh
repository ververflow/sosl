# SOSL Domain Config: Accessibility
# Lighthouse a11y is more stable than perf, but still noisy
MIN_NOISE_FLOOR=3.0
ALLOWED_PATHS="frontend/src/*"
# Secondary: monitor performance while optimizing accessibility
SECONDARY_DOMAINS="performance"
