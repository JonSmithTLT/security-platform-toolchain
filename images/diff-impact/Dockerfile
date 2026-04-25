# images/diff-impact/Dockerfile
# Diff-to-impact analysis.

ARG BASE_IMAGE=registry.internal/security-platform/spt-base:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.description="SPT diff impact image"

USER root

COPY images/diff-impact/run-diff-impact.sh /usr/local/bin/run-diff-impact
RUN sed -i 's/\r$//' /usr/local/bin/run-diff-impact \
    && chmod +x /usr/local/bin/run-diff-impact

USER spt

ENV TARGET_REPO=/workspace \
    DIFF_BASE="" \
    DIFF_HEAD=HEAD \
    ARTIFACTS_DIR=/artifacts

CMD ["run-diff-impact"]
