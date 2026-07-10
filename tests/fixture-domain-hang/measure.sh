#!/bin/bash
# Suite fixture: a measurement that hangs, to prove the timeout shim and watchdogs.
set -euo pipefail
sleep 300
echo "0"
