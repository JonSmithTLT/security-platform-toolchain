# images/gitnexus/Dockerfile
# Git + Nexus Repository Manager helper — clone repos and push/pull artifacts.

FROM registry.internal/security-platform/spt-base:latest

LABEL org.opencontainers.image.description="SPT git + Nexus artifact helper"

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        curl \
        openssh-client \
    && rm -rf /var/lib/apt/lists/*

COPY images/gitnexus/gitnexus.sh /usr/local/bin/gitnexus
RUN chmod +x /usr/local/bin/gitnexus

USER spt

ENV GIT_REPO="" \
    GIT_REF=HEAD \
    NEXUS_URL="" \
    NEXUS_USER="" \
    NEXUS_PASS="" \
    NEXUS_REPO="" \
    ARTIFACTS_DIR=/artifacts

CMD ["gitnexus"]
