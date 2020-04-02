if !exists('*json_encode') || !exists('*json_decode')
  finish
endif

command! DebugRun call dap#run('%')
command! DebugRunLast call dap#run_last()
command! Break call dap#toggle_breakpoint('%', '.')
command! ClearBreakpoints call dap#clear_breakpoints()
command! Continue call dap#continue_stopped()
command! Restart call dap#restart()
command! Step call dap#next_stopped()
command! StepIn call dap#step_in_stopped()
command! StepOut call dap#step_out_stopped()

" TODO: add a command for showing breakpoint locations in the quickfix window
