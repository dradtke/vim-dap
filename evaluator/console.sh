#!/usr/bin/env bash

echo "$$" > /tmp/vim-dap-eval-console-pid

# TODO: support completions by writing to input with a "?" prefix
input_socket=/tmp/vim-dap-eval-input
output_result_socket=/tmp/vim-dap-eval-output-result
output_completion_socket=/tmp/vim-dap-eval-output-completion

rm -f "${output_result_socket}"; mkfifo "${output_result_socket}"
rm -f "${output_completion_socket}"; mkfifo "${output_completion_socket}"

ctrl_c() {
  echo 'interrupt'
}

trap ctrl_c SIGINT

while true; do
  echo -n 'Debug Console> '
  line="$(head -n1 /dev/stdin)"
  status=$?
  if [[ ${status} -ne 0 ]]; then
    echo "exiting with ${status} (current line: $(cat /dev/stdin))"
    exit "${status}"
  fi
  line=$(echo "${line}" | sed 's/^ *//g' | sed 's/ *$//g')
  if [[ -z "${line}" ]]; then
    continue
  fi
  if [[ "${line}" = ':exit' ]]; then
    break
  fi
  length="${#line}"
  echo "$(( ${length} + 1 )):!${line}" > "${input_socket}"
  cat "${output_result_socket}"
done
history -w
