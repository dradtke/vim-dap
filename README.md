# vim-dap

`vim-dap` is a Vim plugin for integrating with the
[Debug Adapter Protocol](https://microsoft.github.io/debug-adapter-protocol/).
to provide full debugger functionality for Vim. Unlike other debugger plugins,
it doesn't attempt to replicate the user interface of an IDE; instead,
interaction with the debugger happens in the terminal, through a fully
readline-enabled debugger console:

![demo](misc/demo.gif)

## Supported Languages

This plugin is intended to be as configuration-free as possible, but this section
will detail existing language support and their requirements.

### Java

Java requires you to be running the
[eclipse.jdt.ls](https://github.com/eclipse/eclipse.jdt.ls) language server
with [java-debug](https://github.com/microsoft/java-debug) installed.  The
`dap#run()` method requires you to be using either `vim-lsp` or
`LanguageClient-neovim` as your client, but `dap#connect()` can be called
manually to connect to the debug adapter if it's already running.

In order to run the language server with debug support, you will need to
initialize the server with the path of the debug jar bundle. An example using
`settings.json`:

```json
{
  "initializationOptions": {
    "bundles": ["/path/to/java-debug.jar"]
  }
}
```

#### Tips

To make it easier to run Java tests, I recommend adding something like this to your `.vimrc`.
With this in place, you can use `\rb` to run all tests in the current file, `\rf` to only run
the test which your cursor is in, and `\rl` to re-run the most recent test.

```viml
au filetype java nmap <Leader>rb :call dap#lang#java#run_test_class()<cr>
au filetype java nmap <Leader>rf :call dap#lang#java#run_test_method()<cr>
au filetype java nmap <Leader>rl :call dap#run_last()<cr>
```

### Go

First, make sure that you have Delve installed and that `dlv` is available on your PATH.

Second, the debug adapter for Go is implemented as part of `vscode-go`, so your
system must have Node available in order for it to run (womp womp). It will be
automatically downloaded on first use.

<!-- vim: set textwidth=80: -->
