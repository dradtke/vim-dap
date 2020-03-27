# vim-dap

`vim-dap` is a Vim plugin for integrating with the
[Debug Adapter Protocol](https://microsoft.github.io/debug-adapter-protocol/).
to provide full debugger functionality for Vim. Unlike other debugger plugins,
it doesn't attempt to replicate the user interface of an IDE; instead,
interaction with the debugger happens in the terminal, through a fully
readline-enabled debugger console:

![demo](misc/demo.gif)

So far this has only been tested with
[eclipse.jdt.ls](https://github.com/eclipse/eclipse.jdt.ls) and
[java-debug](https://github.com/microsoft/java-debug), but should work for any
language that has a language server implementing the debug protocol.
