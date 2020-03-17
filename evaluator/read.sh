#!/usr/bin/env sh
#
# This script repeatedly cats the input socket so that Vim gets notified
# whenever there's new data.
#

input_socket=/tmp/vim-dap-eval-input

rm -f "${input_socket}"
mkfifo "${input_socket}"

while true; do
  cat "${input_socket}"
done
