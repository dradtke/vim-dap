input_socket=/tmp/vim-dap-eval-input

rm -f "${input_socket}"; mkfifo "${input_socket}"

while true; do
  if read line; then
    echo "${line}"
  fi
done < "${input_socket}"
