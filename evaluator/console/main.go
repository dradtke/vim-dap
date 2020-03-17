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
	"unicode"

	"github.com/abiosoft/readline"
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
)

func main() {
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
	shell.NotFound(handler)
	shell.CustomCompleter(completer{})
	shell.Run()
}

func writePid() error {
	pid := strconv.Itoa(os.Getpid())
	if err := ioutil.WriteFile(pidFilepath, []byte(pid), 0644); err != nil {
		return fmt.Errorf("failed to write pid file: %s", err)
	}
	return nil
}

func openInputSocket() error {
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
	s := fmt.Sprintf("%d:%s\n", len(expr), expr)
	if _, err := inputSocket.WriteString(s); err != nil {
		log.Fatalf("failed to write to input socket: %s", err)
	}
}

func handler(c *ishell.Context) {
	writeInput('!', strings.Join(c.RawArgs, " "))
	fmt.Println(<-results)
}

type completer struct{}

// NOTE: this function currently assumes that we are only completing the current word,
// which is defined as the first non-alphanumeric character before pos (exclusive) up
// to pos.
func (c completer) Do(line []rune, pos int) ([][]rune, int) {
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
