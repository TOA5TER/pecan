ARG BASE_IMAGE=node:24-bookworm-slim
FROM ${BASE_IMAGE}

ARG EXTRA_PACKAGES=""
ARG PECAN_USER=pecan
ARG PECAN_HOME=/home/pecan

RUN [ "$(printf '%s' "${EXTRA_PACKAGES}" | wc -l | tr -d ' ')" -eq 0 ] && \
    { [ -z "${EXTRA_PACKAGES}" ] || printf '%s\n' "${EXTRA_PACKAGES}" | grep -Eq '^([A-Za-z0-9][A-Za-z0-9+_.:-]*)( [A-Za-z0-9][A-Za-z0-9+_.:-]*)*$'; } && \
    [ "$(printf '%s' "${PECAN_USER}" | wc -l | tr -d ' ')" -eq 0 ] && \
    printf '%s\n' "${PECAN_USER}" | grep -Eq '^[A-Za-z_][A-Za-z0-9_-]*$' && \
    [ "$(printf '%s' "${PECAN_HOME}" | wc -l | tr -d ' ')" -eq 0 ] && \
    printf '%s\n' "${PECAN_HOME}" | grep -Eq '^/[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$'

RUN apt-get update && \
    apt-get install -y --no-install-recommends bash ca-certificates git ripgrep ${EXTRA_PACKAGES} && \
    rm -rf /var/lib/apt/lists/*

RUN npm install -g --ignore-scripts @earendil-works/pi-coding-agent

RUN useradd -m -d "${PECAN_HOME}" "${PECAN_USER}" && \
    mkdir -p "${PECAN_HOME}/.pi/agent" && \
    chown -R "${PECAN_USER}:${PECAN_USER}" "${PECAN_HOME}/.pi"

ENV PECAN_USER=${PECAN_USER}
ENV PECAN_HOME=${PECAN_HOME}
ENV HOME=${PECAN_HOME}

COPY scripts/run-hooks.sh /usr/local/bin/pecan-run-hooks.sh
COPY hooks.d/build.d/ /opt/pecan-build/hooks.d/build.d/
RUN chmod +x /usr/local/bin/pecan-run-hooks.sh && \
    /usr/local/bin/pecan-run-hooks.sh /opt/pecan-build/hooks.d/build.d && \
    chown -R "${PECAN_USER}:${PECAN_USER}" "${PECAN_HOME}" && \
    rm -rf /opt/pecan-build

USER ${PECAN_USER}
WORKDIR ${PECAN_HOME}

ENTRYPOINT ["pi"]
