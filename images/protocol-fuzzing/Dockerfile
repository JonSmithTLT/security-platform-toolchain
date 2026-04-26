# images/protocol-fuzzing/Dockerfile
# Boofuzz-based protocol/session fuzzing image.

ARG BASE_IMAGE=registry.internal/security-platform/spt-base:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.description="SPT protocol fuzzing image (boofuzz)"

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        iproute2 \
        netcat-openbsd \
        procps \
        psmisc \
        socat \
        sqlite3 \
        tcpdump \
        tshark \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir boofuzz==0.4.2 scapy==2.5.0

COPY images/protocol-fuzzing/run-boofuzz.sh /usr/local/bin/run-boofuzz
COPY images/protocol-fuzzing/run-protocol-fuzzing.sh /usr/local/bin/run-protocol-fuzzing
COPY images/protocol-fuzzing/start-target.sh /usr/local/bin/start-target
COPY images/protocol-fuzzing/stop-target.sh /usr/local/bin/stop-target
COPY images/protocol-fuzzing/capture-pcap.sh /usr/local/bin/capture-pcap
COPY images/protocol-fuzzing/replay-boofuzz-case.sh /usr/local/bin/replay-boofuzz-case
COPY images/protocol-fuzzing/emit-protocol-report.sh /usr/local/bin/emit-protocol-report
COPY images/protocol-fuzzing/toy-boofuzz-campaign.py /usr/local/lib/spt/toy-boofuzz-campaign.py
COPY images/protocol-fuzzing/toy-target.py /usr/local/lib/spt/toy-target.py

RUN sed -i 's/\r$//' /usr/local/bin/run-boofuzz /usr/local/bin/run-protocol-fuzzing /usr/local/bin/start-target /usr/local/bin/stop-target /usr/local/bin/capture-pcap /usr/local/bin/replay-boofuzz-case /usr/local/bin/emit-protocol-report /usr/local/lib/spt/toy-boofuzz-campaign.py /usr/local/lib/spt/toy-target.py \
    && chmod +x /usr/local/bin/run-boofuzz /usr/local/bin/run-protocol-fuzzing /usr/local/bin/start-target /usr/local/bin/stop-target /usr/local/bin/capture-pcap /usr/local/bin/replay-boofuzz-case /usr/local/bin/emit-protocol-report /usr/local/lib/spt/toy-boofuzz-campaign.py /usr/local/lib/spt/toy-target.py

USER spt

ENV PROTOCOL_NAME=toy \
    PROTOCOL_TARGET_HOST=127.0.0.1 \
    PROTOCOL_TARGET_PORT=9001 \
    BOOFUZZ_SCRIPT=/usr/local/lib/spt/toy-boofuzz-campaign.py \
    TARGET_START_CMD="python3 /usr/local/lib/spt/toy-target.py" \
    PROTOCOL_TIMEOUT=30 \
    ARTIFACTS_DIR=/artifacts

CMD ["run-protocol-fuzzing"]
