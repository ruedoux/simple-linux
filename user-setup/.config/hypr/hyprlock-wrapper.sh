#!/usr/bin/env bash
hyprlock
if [ $? -eq 0 ]; then
  sl-controller.sh reload-quickshell
fi
