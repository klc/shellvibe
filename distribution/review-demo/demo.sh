#!/bin/sh
# ShellVibe app-review demo host. Lives in /opt/shellvibe-demo on the server.
#   demo.sh build   build the image (host keys are created once, password read from ./demo-password)
#   demo.sh reset   recreate the container: fresh home directory, all processes gone (cron, nightly)
set -eu
cd "$(dirname "$0")"

case "${1:-}" in
build)
  [ -s demo-password ] || { echo "demo-password missing" >&2; exit 1; }
  if [ ! -d hostkeys ]; then
    mkdir -m 700 hostkeys
    for t in ed25519 ecdsa rsa; do ssh-keygen -q -t "$t" -N '' -C shellvibe-demo -f "hostkeys/ssh_host_${t}_key"; done
  fi
  # --no-cache: BuildKit does not key the cache on secret contents, so a new password would be ignored.
  docker build --no-cache --secret id=demo_password,src=demo-password -t shellvibe-demo .
  exec "$0" reset
  ;;
reset)
  docker rm -f shellvibe-demo >/dev/null 2>&1 || true
  # No network at all: sshd is reached through `docker exec` by shellvibe-demo-ssh.socket.
  # tmpfs counts against --memory, so home + tmp + processes share the 256 MB.
  # --memory-swap is 1 MB above --memory: when they are equal runc leaves memory.swap.max at "max" on cgroup v2.
  docker run -d --name shellvibe-demo --hostname shellvibe-demo --restart unless-stopped --init \
    --network none --read-only \
    --tmpfs /home/demo:rw,exec,nosuid,nodev,size=64m,mode=755 \
    --tmpfs /tmp:rw,noexec,nosuid,nodev,size=16m \
    --tmpfs /run:rw,noexec,nosuid,nodev,size=1m \
    --cpus 0.5 --memory 256m --memory-swap 257m --pids-limit 128 --ulimit nofile=1024 \
    --cap-drop ALL --cap-add CHOWN --cap-add SETUID --cap-add SETGID --cap-add SYS_CHROOT --cap-add AUDIT_WRITE \
    --security-opt no-new-privileges \
    shellvibe-demo >/dev/null
  ;;
*)
  echo "usage: $0 build|reset" >&2
  exit 2
  ;;
esac
