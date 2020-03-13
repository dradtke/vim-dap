input_socket=/tmp/vim-dap-eval-input

while true; do
  if read line; then
    echo "${line}"
  fi
done < "${input_socket}"
