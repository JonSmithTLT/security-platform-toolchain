# images/eval-runner/Dockerfile
# Offline platform and RAG evaluations.

ARG BASE_IMAGE=registry.internal/security-platform/spt-base:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.description="SPT eval runner image"

USER root

COPY images/eval-runner/eval-runner.py /usr/local/lib/spt/eval-runner.py
COPY images/eval-runner/run-eval-runner.sh /usr/local/bin/run-eval-runner
RUN sed -i 's/\r$//' \
        /usr/local/lib/spt/eval-runner.py \
        /usr/local/bin/run-eval-runner \
    && chmod +x /usr/local/bin/run-eval-runner

USER spt

ENV EVAL_CASES=/eval/cases.jsonl \
    ARTIFACTS_DIR=/artifacts

CMD ["run-eval-runner"]
