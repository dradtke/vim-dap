package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"net"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode"

	"github.com/abiosoft/readline"
	"github.com/fatih/color"
	"gopkg.in/abiosoft/ishell.v2"
)

func main() {
	log.SetFlags(log.Ltime | log.Lshortfile)

	var (
		clientAddrFile = flag.String("clientaddrfile", "", "file to write client connection information to")
		progPortFile   = flag.String("progportfile", "", "file to write program connection information to")
		progType       = flag.String("progtype", "", "type of the running program, i.e. 'java'")
		logFile        = flag.String("log", "", "path to log file")
		historyFile    = flag.String("history", "", "path to history file")
		vimMode        = flag.Bool("vim", false, "enable vim mode")
	)
	flag.Parse()

	defer func() {
		if r := recover(); r != nil {
			log.Printf("console panicked: %s", r)
		}
	}()

	if *clientAddrFile == "" {
		panic("-clientaddrfile not specified")
	}

	if *logFile != "" {
		if f, err := os.Create(*logFile); err != nil {
			panic(err)
		} else {
			log.SetOutput(f)
			defer f.Close()
		}
	}

	originalTermState, err := readline.GetState(readline.GetStdin())
	if err != nil {
		panic("failed to get terminal state: " + err.Error())
	}
	defer restore(originalTermState)
	defer fmt.Println()

	programListener, cleanupProgramListener := openListener(*progPortFile, writePort)
	defer cleanupProgramListener()

	clientListener, cleanupClientListener := openListener(*clientAddrFile, writeAddr)
	defer cleanupClientListener()

	clientConn, err := clientListener.Accept()
	if err != nil {
		panic("failed to accept connection: " + err.Error())
	}

	dc := newDebugConsole(clientConn, *progType, programListener, &readline.Config{
		Prompt:      "Debug Console> ",
		HistoryFile: *historyFile,
		VimMode:     *vimMode,
	})

	var wg sync.WaitGroup
	dc.processInput(&wg)
	dc.handleProgramConnections(&wg)

	for {
		fmt.Println(color.YellowString("Program is running..."))
		location, ok := <-dc.ready
		if !ok {
			break
		}
		color.New(color.FgYellow).Printf("Stopped at %s\n", location)
		dc.shell.Start()
		dc.shell.Wait()
	}

	fmt.Println(color.YellowString("Exiting."))
	time.Sleep(5 * time.Second)

	if programListener != nil {
		if err := programListener.Close(); err != nil {
			log.Printf("error closing program listener: %s", err)
		}
	}
	if err := dc.clientConn.Close(); err != nil {
		log.Printf("error closing client connection: %s", err)
	}

	wg.Wait()
}

func openListener(infoFile string, serializer func(net.Addr) []byte) (net.Listener, func()) {
	if infoFile == "" {
		return nil, func() {}
	}
	// Listen to localhost on ipv4, and get a randomly-assigned port.
	listener, err := net.Listen("tcp", "127.0.0.1:")
	if err != nil {
		panic("listen error: " + err.Error())
	}

	if err := ioutil.WriteFile(infoFile, serializer(listener.Addr()), 0644); err != nil {
		listener.Close()
		panic("failed to write info file: " + err.Error())
	}

	return listener, func() {
		listener.Close()
		os.Remove(infoFile)
	}
}

func writeAddr(addr net.Addr) []byte {
	return []byte(addr.String())
}

func writePort(addr net.Addr) []byte {
	return []byte(strconv.Itoa(addr.(*net.TCPAddr).Port))
}

func restore(state *readline.State) {
	if err := readline.Restore(readline.GetStdin(), state); err != nil {
		log.Printf("failed to restore terminal state: %s", err)
	}
}

type debugConsole struct {
	shell                       *ishell.Shell
	clientConn                  net.Conn
	programType                 string
	programListener             net.Listener
	results, completions, ready chan string
}

func newDebugConsole(clientConn net.Conn, programType string, programListener net.Listener, config *readline.Config) *debugConsole {
	dc := &debugConsole{
		shell:           ishell.NewWithConfig(config),
		clientConn:      clientConn,
		programType:     programType,
		programListener: programListener,
		results:         make(chan string, 1),
		completions:     make(chan string, 1),
		ready:           make(chan string),
	}

	dc.shell.AddCmd(&ishell.Cmd{
		Name:    "continue",
		Aliases: []string{"c"},
		Help:    "continue execution after stopping",
		Func:    dc.cmdContinue,
	})
	dc.shell.AddCmd(&ishell.Cmd{
		Name:    "help",
		Aliases: []string{"?"},
		Help:    "print this help text",
		Func:    func(c *ishell.Context) { c.Println(c.HelpText()) },
	})
	dc.shell.AddCmd(&ishell.Cmd{
		Name:    "eval",
		Aliases: []string{"!"},
		Help:    "evaluate the rest of the line in the debuggee's context",
		Func:    dc.cmdEval,
	})
	dc.shell.AddCmd(&ishell.Cmd{
		Name: "scopes",
		Help: "see available scopes",
		Func: dc.cmdScopes,
	})
	dc.shell.AddCmd(&ishell.Cmd{
		Name:    "step",
		Aliases: []string{"next", "s"},
		Help:    "move forward one step",
		Func:    dc.cmdStep,
	})

	dc.shell.CustomCompleter(dc)
	dc.shell.NotFound(dc.notFound)
	dc.shell.EOF(dc.cmdContinue)
	// Setting an empty interrupt function prevents it from exiting the console.
	dc.shell.Interrupt(func(c *ishell.Context, count int, input string) {})

	return dc
}

func (dc *debugConsole) processInput(wg *sync.WaitGroup) {
	wg.Add(1)
	go func() {
		defer dc.shell.Close()
		defer wg.Done()

		r := bufio.NewReader(dc.clientConn)
		for {
			chunk, err := r.ReadString('#')
			if err == io.EOF {
				close(dc.ready)
				return
			}
			if err != nil {
				panic("error reading input: %s" + err.Error())
			}

			inputLength, err := strconv.Atoi(chunk[:len(chunk)-1])
			if err != nil {
				panic(err)
			}

			b := make([]byte, inputLength)
			if _, err := io.ReadFull(r, b); err != nil {
				panic(err)
			}

			indicator := b[0]
			rest := string(b[1:])

			switch indicator {
			case '@':
				dc.ready <- rest
			case '!':
				dc.results <- rest
			case '?':
				// never block on sending a completion result, so only send it if there's space in the buffer
				if len(dc.completions) < cap(dc.completions) {
					dc.completions <- rest
				}
			default:
				log.Printf("unknown input indicator: %v", indicator)
			}
		}
	}()
}

func (dc *debugConsole) handleProgramConnections(wg *sync.WaitGroup) {
	if dc.programListener == nil {
		return
	}
	wg.Add(1)
	go func() {
		defer wg.Done()
		for {
			conn, err := dc.programListener.Accept()
			if err != nil {
				return
			}
			wg.Add(1)
			go func() {
				defer wg.Done()
				switch dc.programType {
				case "java":
					dc.processJUnitOutput(conn)
				default:
					// nothing to do
				}
			}()
		}
	}()
}

func (dc *debugConsole) processJUnitOutput(conn net.Conn) {
	const (
		testRunStart = "%TESTC"
		testRunEnd   = "%RUNTIME"
		testStart    = "%TESTS"
		testEnd      = "%TESTE"
		testFailed   = "%FAILED"
		testError    = "%ERROR"
		traceStart   = "%TRACES"
		traceEnd     = "%TRACEE"
	)
	var (
		scanner = bufio.NewScanner(conn)
		inTrace bool
	)
	for scanner.Scan() {
		line := scanner.Text()
		if !inTrace && strings.HasPrefix(line, traceStart) {
			inTrace = true
			continue
		}
		if inTrace && strings.HasPrefix(line, traceEnd) {
			inTrace = false
			continue
		}
		if inTrace {
			dc.writeQuickfix(line)
			continue
		}
		if strings.HasPrefix(line, testRunStart) {
			fields := strings.Fields(line)
			if len(fields) != 3 {
				log.Printf("%s expected 3 fields, got %d", testRunStart, len(fields))
				return
			}
			if fields[2] != "v2" {
				log.Printf("%s expected v2, got %s", fields[2])
				return
			}
			dc.writeQuickfix("Running %s tests", fields[1])
		} else if strings.HasPrefix(line, testRunEnd) {
			elapsedMillis := line[len(testRunEnd):]
			dc.writeQuickfix("Test run finished in %s milliseconds", elapsedMillis)
		} else if strings.HasPrefix(line, testStart) {
			fields := strings.Fields(line)
			if len(fields) != 2 {
				log.Printf("%s expected 2 fields, got %d", testStart, len(fields))
				return
			}
			fields = strings.Split(fields[1], ",") // testID,testName
			dc.writeQuickfix("Test started: %s", fields[1])
		} else if strings.HasPrefix(line, testEnd) {
			fields := strings.Fields(line)
			if len(fields) != 2 {
				log.Printf("%s expected 2 fields, got %d", testEnd, len(fields))
				return
			}
			fields = strings.Split(fields[1], ",") // testID,testName
			dc.writeQuickfix("Test ended: %s", fields[1])
		} else if strings.HasPrefix(line, testFailed) || strings.HasPrefix(line, testError) {
			fields := strings.Fields(line)
			if len(fields) != 2 {
				log.Printf("%s expected 2 fields, got %d", testFailed+" or "+testError, len(fields))
				return
			}
			fields = strings.Split(fields[1], ",") // testID,testName
			dc.writeQuickfix("Test errored or failed: %s", fields[1])
		} else {
			log.Printf("unknown: %s", line)
		}
	}
	if scanner.Err() != nil {
		log.Printf("program output reader encountered unexpected error: %s", scanner.Err())
	}
}

func (dc *debugConsole) writeQuickfix(line string, v ...interface{}) {
	dc.writeOutput('q', fmt.Sprintf(line, v...))
}

func (dc *debugConsole) writeOutput(action rune, line string) {
	expr := string(action) + line
	log.Printf("writing line: %s", fmt.Sprintf("%d#%s", len(expr), expr))
	if _, err := fmt.Fprintf(dc.clientConn, "%d#%s\n", len(expr), expr); err != nil {
		panic("failed to write to input socket: " + err.Error())
	}
}

// Do implements the custom completer interface.
func (dc debugConsole) Do(line []rune, pos int) ([][]rune, int) {
	start := string(line[:pos])
	firstSpace := strings.Index(start, " ")

	if firstSpace == -1 {
		return dc.cmdEvalCompleter(line, pos)
	}

	command := start[:firstSpace]
	line = line[firstSpace:]
	pos -= firstSpace

	// if multiple words, complete based on the available command
	switch command {
	case "eval", "!":
		return dc.cmdEvalCompleter(line, pos)
	default:
		return nil, 0
	}
}

func (dc *debugConsole) cmdContinue(c *ishell.Context) {
	dc.writeOutput(':', "continue")
	c.Println(color.GreenString("continuing"))
	c.Println()
	dc.shell.Stop()
}

func (dc *debugConsole) cmdEval(c *ishell.Context) {
	dc.doEval(c, c.RawArgs[1:])
}

func (dc *debugConsole) notFound(c *ishell.Context) {
	dc.doEval(c, c.RawArgs)
}

func (dc *debugConsole) doEval(a ishell.Actions, args []string) {
	dc.writeOutput('!', strings.Join(args, " "))
	a.Println(color.CyanString(<-dc.results))
}

func (dc *debugConsole) cmdScopes(c *ishell.Context) {
	dc.writeOutput(':', "scopes")

	type variable struct {
		Name  string `json:"name"`
		Value string `json:"value"`
	}

	var scopes map[string][]variable
	if err := json.Unmarshal([]byte(<-dc.results), &scopes); err != nil {
		panic("failed to parse scopes: %s" + err.Error())
	}

	cf := color.CyanString

	for scope, vars := range scopes {
		c.Println(cf(scope))
		for _, v := range vars {
			c.Printf(cf("    %s = %s\n"), v.Name, v.Value)
		}
	}
	c.Println("")
}

func (dc *debugConsole) cmdStep(c *ishell.Context) {
	dc.writeOutput(':', "next")
	c.Println(color.GreenString("stepping"))
	c.Println()
	dc.shell.Stop()
}

func (dc *debugConsole) cmdEvalCompleter(line []rune, pos int) ([][]rune, int) {
	dc.writeOutput('?', strconv.Itoa(pos+1)+"|"+string(line))

	wordBreak := -1
	for i := pos - 1; i >= 0; i-- {
		if !unicode.IsLetter(line[i]) && !unicode.IsDigit(line[i]) {
			wordBreak = i
			break
		}
	}
	prefix := string(line[wordBreak+1 : pos])

	// NOTE: this wordBreak != . check assumes a C-like language. Technically, it should
	// be checking whether the character(s) at wordBreak represent a method call, and if
	// so, completion should continue.
	if wordBreak > -1 && line[wordBreak] != '.' && len(prefix) == 0 {
		return nil, pos
	}

	var items []map[string]interface{}
	if err := json.Unmarshal([]byte(<-dc.completions), &items); err != nil {
		panic("failed to parse completion items: %s" + err.Error())
	}

	if len(items) == 0 {
		return nil, 0
	}

	var newLine [][]rune
	for _, item := range items {
		var text string
		if item["text"] != nil {
			text = item["text"].(string)
		} else if item["label"] != nil {
			text = item["label"].(string)
		} else {
			continue
		}
		if strings.HasPrefix(text, prefix) {
			rest := text[len(prefix):]
			newLine = append(newLine, []rune(rest))
		}
	}

	return newLine, len(prefix)
}

func writePid(path string) error {
	pid := strconv.Itoa(os.Getpid())
	if err := ioutil.WriteFile(path, []byte(pid), 0644); err != nil {
		return fmt.Errorf("failed to write pid file: %s", err)
	}
	return nil
}
