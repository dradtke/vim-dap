if !exists('*json_encode') || !exists('*json_decode')
  finish
endif

command! DebugRun call dap#run('%')
command! DebugRunLast call dap#run_last()
command! Break call dap#toggle_breakpoint('%', '.')
command! ClearBreakpoints call dap#clear_breakpoints()
command! Continue call dap#continue_stopped()
command! Restart call dap#restart()
command! -nargs=? Evaluate call dap#evaluate(<args>)
command! Step call dap#next_stopped()
command! StepIn call dap#step_in_stopped()
command! StepOut call dap#step_out_stopped()
command! Locals call dap#show_scope('Local')
command! -nargs=1 Local call dap#show_scope_var('Local', <args>)

let s:filename = expand('<sfile>:p')
let s:plugin_home = fnamemodify(s:filename, ':h:h')

function! s:debug_console_built(job_id, data, event_type) abort
  if a:data == 0
    echomsg 'vim-dap: Debug Console binary built successfully'
  else
    echoerr 'vim-dap: Failed to build Debug Console binary, will not be available for debugging'
  endif
endfunction

function! s:debug_console_build_stdout(job_id, data, event_type) abort
  echo join(a:data, "\n")
endfunction

function! s:debug_console_build_stderr(job_id, data, event_type) abort
  echo join(a:data, "\n")
endfunction

if !executable(s:plugin_home.'/evaluator/console/main')
  if !executable('go')
    " TODO: support downloading pre-built binaries?
    echoerr 'vim-dap: Go not found, Debug Console will not be available for debugging'
  else
    echomsg 'vim-dap: Building Debug Console binary'
    call dap#async#job#start(['go', 'build', 'main.go'], {
          \ 'cwd': s:plugin_home.'/evaluator/console',
          \ 'on_exit': function('s:debug_console_built'),
          \ 'handle_stdout': function('s:debug_console_build_stdout'),
          \ 'handle_stderr': function('s:debug_console_build_stderr'),
          \ })
  endif
endif
