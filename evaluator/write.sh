#!/usr/bin/env bash

# TODO: support completions by writing to input with a "?" prefix
input_socket=/tmp/vim-dap-eval-input
output_result_socket=/tmp/vim-dap-eval-output-result
output_completion_socket=/tmp/vim-dap-eval-output-completion

if [ ! -e "${input_socket}" ]; then
  mkfifo "${input_socket}"
fi
if [ ! -e "${output_result_socket}" ]; then
  mkfifo "${output_result_socket}"
fi
if [ ! -e "${output_completion_socket}" ]; then
  mkfifo "${output_completion_socket}"
fi

good_input=1

ctrl_c() {
  good_input=0
  # This isn't ideal, since the read still hangs, but I'm not sure how to tell it to quit.
}

trap ctrl_c SIGINT

history -r /tmp/vim-dap-eval-history
while true; do
  read -e -p "Debug Console> " line
  status=$?
  if [[ ${good_input} -eq 0 ]]; then
    good_input=1
    continue
  fi
  if [[ ${status} -ne 0 ]]; then
    exit $?
  fi
  line=$(echo "${line}" | sed 's/^ *//g' | sed 's/ *$//g')
  if [[ -z "${line}" ]]; then
    continue
  fi
  if [[ "${line}" = ':exit' ]]; then
    break
  fi
  length="${#line}"
  history -s "${line}"
  echo "$(( ${length} + 1 )):!${line}" > "${input_socket}"
  cat "${output_result_socket}"
done
history -w
