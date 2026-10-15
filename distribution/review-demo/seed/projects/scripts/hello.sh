#!/bin/sh
echo "Hello, $(whoami)! This is $(hostname), up $(uptime -p | sed 's/^up //')."
