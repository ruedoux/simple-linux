#!/usr/bin/env bash
hyprlock
if [ $? -eq 0 ]; then
  sl-user controller reload-quickshell
fi
