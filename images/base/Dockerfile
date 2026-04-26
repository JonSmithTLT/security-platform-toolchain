# syntax=docker/dockerfile:1
# images/base/Dockerfile
# Base image for all security-platform-toolchain tool images.
# Provides: Python 3, common OS packages, shared scripts, and non-root user.

FROM ubuntu:24.04

LABEL org.opencontainers.image.source="https://github.com/JonSmithTLT/security-platform-toolchain" \
      org.opencontainers.image.description="SPT base image" \
      org.opencontainers.image.licenses="MIT"

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive \
    PIP_BREAK_SYSTEM_PACKAGES=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        jq \
        python3 \
        python3-pip \
        python3-venv \
        tini \
        unzip \
        wget

RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install jsonschema==4.23.0

# ── Shared scripts ──────────────────────────────────────────────────────────
RUN mkdir -p /usr/local/lib/spt /usr/local/share/spt/schemas /artifacts

COPY common/logging.sh    /usr/local/lib/spt/logging.sh
COPY common/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY common/emit-job-report.py /usr/local/bin/emit-job-report
COPY common/emit-artifact-manifest.py /usr/local/bin/emit-artifact-manifest
COPY common/spt-stub-tool.sh /usr/local/bin/spt-stub-tool
COPY schemas/             /usr/local/share/spt/schemas/

RUN sed -i 's/\r$//' \
        /usr/local/lib/spt/logging.sh \
        /usr/local/bin/entrypoint.sh \
        /usr/local/bin/emit-job-report \
        /usr/local/bin/emit-artifact-manifest \
        /usr/local/bin/spt-stub-tool \
    && chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/emit-job-report /usr/local/bin/emit-artifact-manifest /usr/local/bin/spt-stub-tool

# ── Non-root user ───────────────────────────────────────────────────────────
RUN groupadd --gid 1001 spt && \
    useradd --uid 1001 --gid spt --shell /bin/bash --create-home spt

VOLUME ["/artifacts"]
WORKDIR /workspace

USER spt

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
