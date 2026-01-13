# ZEMACS - Agentic MCP Server
# ===========================
# 
# This Makefile provides a comprehensive developer experience for building,
# testing, analyzing, and deploying the ZEMACS server.

# --- Configuration ---
ZIG := zig
FLAGS := -Doptimize=ReleaseSafe
BIN := zig-out/bin/zemacs
PORT := 3000
FUZZ_RUNNER := fuzz_runner.py

# Colors
GREEN  := $(shell tput -Txterm setaf 2)
YELLOW := $(shell tput -Txterm setaf 3)
BLUE   := $(shell tput -Txterm setaf 4)
RESET  := $(shell tput -Txterm sgr0)

.PHONY: all help build run run-tcp test fuzz fmt clean install-emacs deps

all: help

## ----------------------------------------------------------------------
## 🚀 Core Commands
## ----------------------------------------------------------------------

## Build the project
build:
	@echo "${BLUE}🔨 Building ZEMACS...${RESET}"
	$(ZIG) build $(FLAGS)

## Run in StdIO mode (Single Agent)
run: build
	@echo "${GREEN}▶️  Running ZEMACS (StdIO)...${RESET}"
	./$(BIN)

## Run in TCP mode (Multi-Agent) on port 3000
run-tcp: build
	@echo "${GREEN}▶️  Running ZEMACS (TCP :${PORT})...${RESET}"
	./$(BIN) -mode tcp -port $(PORT)

## ----------------------------------------------------------------------
## 🛡️ Quality & Safety
## ----------------------------------------------------------------------

## Run Unit Tests
test:
	@echo "${YELLOW}🧪 Running Unit Tests...${RESET}"
	$(ZIG) build test

## Format Code (zig fmt)
fmt:
	@echo "${BLUE}🧹 Formatting Code...${RESET}"
	$(ZIG) fmt src/ clients/

## Run Fuzzing Campaign (Security)
fuzz:
	@echo "${YELLOW}🌪️  Running Fuzz Harness...${RESET}"
	$(ZIG) build-exe src/fuzz.zig --name zemacs-fuzz
	python3 $(FUZZ_RUNNER)
	@rm -f zemacs-fuzz zemacs-fuzz.o

## ----------------------------------------------------------------------
## 📦 Installation
## ----------------------------------------------------------------------

## Install Emacs Client
install-emacs:
	@echo "${BLUE}📦 Installing Emacs Client...${RESET}"
	@mkdir -p ~/.emacs.d/lisp
	@cp clients/emacs/zemacs-client.el ~/.emacs.d/lisp/
	@# Update path in the client file
	@sed -i 's|~/Project/zemacs/zig-out/bin/zemacs|$(shell pwd)/$(BIN)|g' ~/.emacs.d/lisp/zemacs-client.el
	@echo "${GREEN}✅ Installed to ~/.emacs.d/lisp/zemacs-client.el${RESET}"

## Clean artifacts
clean:
	@echo "${BLUE}🗑️  Cleaning up...${RESET}"
	rm -rf zig-out zig-cache zemacs-fuzz *.o crashes/ *.log assets/logo.png.tmp

## ----------------------------------------------------------------------
## ℹ️  Help
## ----------------------------------------------------------------------

## Show this help message
help:
	@echo "${BLUE}ZEMACS Developer Tools${RESET}"
	@awk '/^##/ { printf "${YELLOW}%-20s${RESET} %s\n", substr($$0, 4), getline; }' $(MAKEFILE_LIST)
