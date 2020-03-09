if !exists('*json_encode') || !exists('*json_decode')
  finish
endif

command! Debug call dap#start()
command! Break call dap#toggle_breakpoint('%', '.')
command! Run call dap#configuration_done()
command! Continue call dap#continue_stopped()
command! Restart call dap#restart()
command! -nargs=1 Evaluate call dap#evaluate(<args>)
