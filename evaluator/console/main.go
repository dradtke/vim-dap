package main

import (
	"bufio"
	"fmt"
	"io/ioutil"
	"log"
	"net"
	"os"
	"strconv"
	"strings"

	"github.com/abiosoft/readline"
	"gopkg.in/abiosoft/ishell.v2"
)

const (
	pidFilepath              = "/tmp/vim-dap-eval-console-pid"
	inputFilepath            = "/tmp/vim-dap-eval-input"
	outputResultFilepath     = "/tmp/vim-dap-eval-output-result"
	outputCompletionFilepath = "/tmp/vim-dap-eval-output-completion"
)

var (
	inputSocket    *os.File
	resultListener net.Listener
	resultScanner  *bufio.Scanner
)

func main() {
	log.Println("writing pid...")
	if err := writePid(); err != nil {
		log.Fatal(err)
	}
	log.Println("opening input socket...")
	if err := openInputSocket(); err != nil {
		log.Fatal(err)
	}
	log.Println("opening result socket...")
	if err := openResultListener(); err != nil {
		log.Fatal(err)
	}

	log.Println("running shell...")
	shell := ishell.NewWithConfig(&readline.Config{Prompt: "Debug Console> "})
	shell.NotFound(handler)
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

func openResultListener() error {
	os.Remove(outputResultFilepath)
	var err error
	if resultListener, err = net.Listen("unix", outputResultFilepath); err != nil {
		return fmt.Errorf("failed to open result socket: %s", err)
	}
	go func() {
		for {
			conn, err := resultListener.Accept()
			if err != nil {
				log.Fatalf("failed to accept result connection: %s", err)
			}
			log.Printf("received result connection")
			go func(c net.Conn) {
				b, err := ioutil.ReadAll(c)
				c.Close()
				if err != nil {
					log.Fatalf("failed to read connection data: %s", err)
				}
				fmt.Println("result data: " + string(b))
			}(conn)
		}
	}()
	return nil
}

func handler(c *ishell.Context) {
	s := strings.Join(c.RawArgs, " ")
	if _, err := inputSocket.WriteString("!" + s + "\n"); err != nil {
		log.Fatalf("failed to write to input socket: %s", err)
	}
	/*
		if resultScanner.Scan() {
			fmt.Println(resultScanner.Text())
		} else {
			if resultScanner.Err() != nil {
				log.Fatalf("failed to read from result socket: %s", resultScanner.Err())
			} else {
				log.Fatal("result socket EOF")
			}
		}
	*/
}
