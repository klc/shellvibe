# Verification harness for the Mosh transport (docs/mosh_integration_plan.md, Faz 0).
# Not shipped with the app: this only exists so the Dart client can be run
# against a real `mosh-server` before Faz 1 builds anything on top of it.
FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        openssh-server \
        mosh \
        locales \
        ca-certificates \
    && sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen \
    && locale-gen \
    && rm -rf /var/lib/apt/lists/*

# Password auth against a throwaway account. The harness is bound to loopback
# only (see docker-compose.yml), so this never faces the network.
RUN useradd --create-home --shell /bin/bash mosh \
    && echo 'mosh:mosh' | chpasswd \
    && mkdir -p /run/sshd

# The UDP range the smoke script asks `mosh-server` for.
EXPOSE 22
EXPOSE 60000-60010/udp

CMD ["/usr/sbin/sshd", "-D", "-e"]
