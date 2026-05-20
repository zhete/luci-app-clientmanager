#!/bin/sh
# Client Manager - Firewall include for rule persistence
# This script is called by the firewall on start/restart to restore rules

/usr/libexec/clientmanager-block.sh restore 2>/dev/null

exit 0
