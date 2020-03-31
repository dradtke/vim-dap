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
	"unicode"

	"github.com/abiosoft/readline"
	"github.com/fatih/color"
	"gopkg.in/abiosoft/ishell.v2"
)

func main() {
	log.SetFlags(log.Ltime | log.Lshortfile)

	var (
		network = flag.String("network", "", "network to connect with")
		address = flag.String("address", "", "address to listen on")
		logfile = flag.String("log", "", "path to log file")
	)
	flag.Parse()

	if *logfile != "" {
		if f, err := os.Create(*logfile); err != nil {
			log.Fatal(err)
		} else {
			log.SetOutput(f)
			defer f.Close()
		}
	}

	originalTermState, err := readline.GetState(readline.GetStdin())
	if err != nil {
		log.Fatalf("failed to get terminal state: %s", err)
	}
	defer restore(originalTermState)
	defer fmt.Println()

	listener, err := net.Listen(*network, *address)
	if err != nil {
		log.Fatalf("listen error: %s", err)
	}
	defer listener.Close()

	conn, err := listener.Accept()
	if err != nil {
		log.Fatalf("failed to accept connection: %s", err)
	}

	dc := newDebugConsole(conn)
	go dc.processInput()
	dc.shell.Run()

	// fmt.Println("quitting")
}

func restore(state *readline.State) {
	if err := readline.Restore(readline.GetStdin(), state); err != nil {
		log.Printf("failed to restore terminal state: %s", err)
	}
}

type debugConsole struct {
	shell                *ishell.Shell
	conn                 net.Conn
	results, completions chan string
}

func newDebugConsole(conn net.Conn) *debugConsole {
	dc := &debugConsole{
		conn:        conn,
		shell:       ishell.NewWithConfig(&readline.Config{Prompt: "Debug Console> "}),
		results:     make(chan string, 1),
		completions: make(chan string, 1),
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
		Aliases: []string{"next"},
		Help:    "move forward one step",
		Func:    dc.cmdStep,
	})

	dc.shell.CustomCompleter(dc)
	dc.shell.NotFound(dc.notFound)
	dc.shell.EOF(dc.cmdContinue)
	// Setting an empty interrupt function prevents it from exiting the console.
	// dc.shell.Interrupt(func(c *ishell.Context, count int, input string) {})

	return dc
}

func (dc *debugConsole) processInput() {
	defer dc.shell.Close()

	r := bufio.NewReader(dc.conn)
	for {
		line, err := r.ReadString('\n')
		if err == io.EOF {
			dc.conn.Close()
			return
		}
		if err != nil {
			log.Fatalf("error reading input: %s", err)
		}

		indicator := line[0]
		rest := line[1:]
		switch indicator {
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
}

func (dc *debugConsole) writeOutput(action rune, line string) {
	expr := string(action) + line
	if _, err := fmt.Fprintf(dc.conn, "%d#%s\n", len(expr), expr); err != nil {
		log.Fatalf("failed to write to input socket: %s", err)
	}
}

// Do implements the custom completer interface.
func (dc debugConsole) Do(line []rune, pos int) ([][]rune, int) {
	start := string(line[:pos])
	firstSpace := strings.Index(start, " ")

	// autocomplete commands if there's only one word so far
	if firstSpace == -1 {
		var newLine [][]rune
		for _, cmd := range dc.shell.Cmds() {
			if strings.HasPrefix(cmd.Name, start) {
				completion := cmd.Name[pos:] + " "
				newLine = append(newLine, []rune(completion))
			}
		}
		return newLine, pos
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
		log.Fatalf("failed to parse scopes: %s", err)
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
}

func (dc *debugConsole) cmdEvalCompleter(line []rune, pos int) ([][]rune, int) {
	dc.writeOutput('?', strconv.Itoa(pos)+"|"+string(line))

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
	if line[wordBreak] != '.' && len(prefix) == 0 {
		return nil, pos
	}

	var items []map[string]interface{}
	if err := json.Unmarshal([]byte(<-dc.completions), &items); err != nil {
		log.Fatalf("failed to parse completion items: %s", err)
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
