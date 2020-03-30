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

Java requires you to be running the [eclipse.jdt.ls](https://github.com/eclipse/eclipse.jdt.ls)
language server with [java-debug](https://github.com/microsoft/java-debug) installed.
The `dap#run()` method requires you to be using `LanguageClient-neovim` as your client,
but `dap#connect()` can be called manually to connect to the debug adapter if it's already
running.

### Go

First, make sure that you have Delve installed and that `dlv` is available on your PATH.

Second, the debug adapter for Go is implemented as part of `vscode-go`, so your
system must have Node available in order for it to run (womp womp). It will be
automatically downloaded on first use.
