# App-review demo host

A sandbox SSH/SFTP server for App Store and Google Play reviewers. One user (`demo`, password
login), no network inside the container, read-only root, home on tmpfs, 0.5 CPU / 256 MB /
128 processes, recreated every night at 04:00.

`shellvibe-demo-ssh.socket` listens on TCP 33022 and runs `docker exec -i shellvibe-demo sshd -i`
per connection, so the container needs no network and the host firewall needs no rules.

## Install or rebuild (on the server, as root)

```sh
# copy this directory to /opt/shellvibe-demo, then put the password (one line, no newline needed)
# in /opt/shellvibe-demo/demo-password with mode 600
cd /opt/shellvibe-demo
./demo.sh build                     # host keys are created on first build and kept afterwards
install -m 644 shellvibe-demo-ssh.socket shellvibe-demo-ssh@.service /etc/systemd/system/
install -m 644 shellvibe-demo.cron /etc/cron.d/shellvibe-demo
systemctl daemon-reload && systemctl enable --now shellvibe-demo-ssh.socket
```

Change the password: edit `demo-password`, run `./demo.sh build`. Reset by hand: `./demo.sh reset`.
