if !exists('*json_encode') || !exists('*json_decode')
  finish
endif

command! -nargs=1 DapConnect call dap#connect('localhost', <args>)
