# images/secrets/Dockerfile
# Secret scanning with Gitleaks and TruffleHog.

FROM ghcr.io/jonsmithtlt/spt-base:latest

LABEL org.opencontainers.image.description="SPT secrets scanning image"

USER root

ARG GITLEAKS_VERSION=8.18.4
ARG TRUFFLEHOG_VERSION=3.79.0

RUN curl -fsSL \
    "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" \
    | tar -xz -C /usr/local/bin gitleaks \
    && curl -fsSL \
    "https://github.com/trufflesecurity/trufflehog/releases/download/v${TRUFFLEHOG_VERSION}/trufflehog_${TRUFFLEHOG_VERSION}_linux_amd64.tar.gz" \
    | tar -xz -C /usr/local/bin trufflehog

COPY images/secrets/run-secrets.sh /usr/local/bin/run-secrets
RUN chmod +x /usr/local/bin/run-secrets

USER spt

ENV TARGET_REPO=/workspace \
    ARTIFACTS_DIR=/artifacts \
    SECRETS_TOOLS=gitleaks,trufflehog

CMD ["run-secrets"]
