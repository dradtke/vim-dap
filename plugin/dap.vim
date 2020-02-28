if !exists('*json_encode') || !exists('*json_decode')
  finish
endif

command! -nargs=1 DapConnect call dap#connect('localhost', <args>)
command! Break call dap#toggle_breakpoint('%', '.')
command! Run call dap#configuration_done()
command! Continue call dap#continue_stopped()
