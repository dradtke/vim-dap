package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"strconv"
	"strings"
	"syscall"
	"time"
	"unicode"

	"github.com/abiosoft/readline"
	"github.com/fatih/color"
	"gopkg.in/abiosoft/ishell.v2"
)

const (
	temp                     = "/tmp/vim-dap"
	pidFilepath              = temp + "/eval-console.pid"
	inputFilepath            = temp + "/eval-input.pipe"
	outputResultFilepath     = temp + "/eval-result.pipe"
	outputCompletionFilepath = temp + "/eval-completion.pipe"
	logFilepath              = temp + "/eval-console.log"
)

var (
	inputSocket *os.File
	results     chan string
	completions chan string

	commands = []*ishell.Cmd{
		&ishell.Cmd{
			Name:    "continue",
			Aliases: []string{"c"},
			Help:    "continue execution after stopping",
			Func:    cmdContinue,
		},
		&ishell.Cmd{
			Name:    "help",
			Aliases: []string{"?"},
			Help:    "print this help text",
			Func:    func(c *ishell.Context) { c.Println(c.HelpText()) },
		},
		&ishell.Cmd{
			Name:    "eval",
			Aliases: []string{"!"},
			Help:    "evaluate the rest of the line in the debuggee's context",
			Func:    cmdEval,
		},
		&ishell.Cmd{
			Name: "scopes",
			Help: "see available scopes",
			Func: cmdScopes,
		},
		&ishell.Cmd{
			Name:    "step",
			Aliases: []string{"next"},
			Help:    "move forward one step",
			Func:    cmdStep,
		},
	}
)

func main() {
	log.SetFlags(log.Ltime | log.Lshortfile)

	if err := os.MkdirAll(temp, 0755); err != nil {
		log.Fatal(err)
	}
	if err := writePid(); err != nil {
		log.Fatal(err)
	}
	if err := openInputSocket(); err != nil {
		log.Fatal(err)
	}
	if ch, err := readFifo(outputResultFilepath); err != nil {
		log.Fatal(err)
	} else {
		results = ch
	}
	if ch, err := readFifo(outputCompletionFilepath); err != nil {
		log.Fatal(err)
	} else {
		completions = ch
	}

	if f, err := os.Create(logFilepath); err != nil {
		log.Fatal(err)
	} else {
		log.SetOutput(f)
		defer f.Close()
	}

	shell := ishell.NewWithConfig(&readline.Config{Prompt: "Debug Console> "})
	for _, cmd := range commands {
		shell.AddCmd(cmd)
	}

	//shell.NotFound(cmdNotFound)
	// TODO: looks like we'll need a custom completer here still
	shell.CustomCompleter(completer{})
	shell.Run()
}

type completer struct {
}

func (c completer) Do(line []rune, pos int) ([][]rune, int) {
	start := string(line[:pos])
	firstSpace := strings.Index(start, " ")

	// autocomplete commands if there's only one word so far
	if firstSpace == -1 {
		var newLine [][]rune
		for _, cmd := range commands {
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
		return cmdEvalCompleter(line, pos)
	}
	return nil, 0
}

func writePid() error {
	pid := strconv.Itoa(os.Getpid())
	if err := ioutil.WriteFile(pidFilepath, []byte(pid), 0644); err != nil {
		return fmt.Errorf("failed to write pid file: %s", err)
	}
	return nil
}

func openInputSocket() error {
	for {
		_, err := os.Stat(inputFilepath)
		if err == nil {
			break
		}
		if !os.IsNotExist(err) {
			return fmt.Errorf("failed to stat: %w", err)
		}
		time.Sleep(1 * time.Second)
	}
	var err error
	if inputSocket, err = os.OpenFile(inputFilepath, os.O_WRONLY|os.O_CREATE, os.ModeNamedPipe); err != nil {
		return fmt.Errorf("failed to open input socket: %s", err)
	}
	return nil
}

func readFifo(path string) (chan string, error) {
	os.Remove(path)
	if err := syscall.Mkfifo(path, 0644); err != nil {
		return nil, fmt.Errorf("failed to make fifo: %s", err)
	}
	ch := make(chan string)
	go func() {
		for {
			b, err := ioutil.ReadFile(path)
			if err != nil {
				log.Fatalf("failed to read from fifo: %s", err)
			}
			ch <- strings.TrimSpace(string(b))
		}
	}()
	return ch, nil
}

func writeInput(action rune, line string) {
	expr := string(action) + line
	log.Printf("sending to vim: %s", expr)
	s := fmt.Sprintf("%d#%s\n", len(expr), expr)
	if _, err := inputSocket.WriteString(s); err != nil {
		log.Fatalf("failed to write to input socket: %s", err)
	}
}

func cmdContinue(c *ishell.Context) {
	writeInput(':', "continue")
	c.Println(color.GreenString("continuing"))
}

func cmdEval(c *ishell.Context) {
	writeInput('!', strings.Join(c.RawArgs[1:], " "))
	c.Println(color.CyanString(<-results))
}

func cmdScopes(c *ishell.Context) {
	writeInput(':', "scopes")

	type variable struct {
		Name  string `json:"name"`
		Value string `json:"value"`
	}

	var scopes map[string][]variable
	if err := json.Unmarshal([]byte(<-results), &scopes); err != nil {
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

func cmdStep(c *ishell.Context) {
	writeInput(':', "next")
	c.Println(color.GreenString("stepping"))
}

func cmdEvalCompleter(line []rune, pos int) ([][]rune, int) {
	writeInput('?', strconv.Itoa(pos)+"|"+string(line))

	wordBreak := -1
	for i := pos - 1; i >= 0; i-- {
		if !unicode.IsLetter(line[i]) && !unicode.IsDigit(line[i]) {
			wordBreak = i
			break
		}
	}
	prefix := string(line[wordBreak+1 : pos])

	var items []map[string]interface{}
	if err := json.Unmarshal([]byte(<-completions), &items); err != nil {
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
