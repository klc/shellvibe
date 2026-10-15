# syntax=docker/dockerfile:1
# Sandbox SSH host for App Store / Play reviewers. Built and run by demo.sh.
FROM debian:trixie-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends openssh-server procps htop nano vim-tiny less tree file tmux \
 && rm -rf /var/lib/apt/lists/* /etc/ssh/ssh_host_* \
 && find / -xdev -type f -perm /6000 -exec chmod ug-s {} + \
 && useradd -M -d /home/demo -s /bin/bash -u 1000 demo \
 && echo 'export LANG=C.UTF-8' > /etc/profile.d/lang.sh

COPY sshd_config /etc/ssh/sshd_config
COPY motd /etc/motd
COPY seed/ /opt/seed/
COPY hostkeys/ /etc/ssh/hostkeys/
RUN --mount=type=secret,id=demo_password,required=true \
    echo "demo:$(cat /run/secrets/demo_password)" | chpasswd

# /home/demo, /tmp and /run are tmpfs (see demo.sh), so every container start is a fresh home.
CMD ["sh", "-c", "mkdir -p -m 755 /run/sshd && cp -rT /etc/skel /home/demo && cp -rT /opt/seed /home/demo && chown -R demo:demo /home/demo && exec sleep infinity"]
