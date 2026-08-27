#!/bin/bash
# Pure helpers for record. Sourced by the script and by tests.
# Do not mkdir, do not start processes.

parse_capture_index() {
  # $1 = ffmpeg -list_devices stderr, $2 = Capture screen N
  printf '%s\n' "$1" | sed -n "s/.*\[\([0-9]*\)\] Capture screen $2/\1/p" | head -1
}

parse_audio_index() {
  # $1 = ffmpeg -list_devices stderr, $2 = exact device name
  printf '%s\n' "$1" | sed -n "s/.*\[\([0-9]*\)\] $2/\1/p" | tail -1
}
