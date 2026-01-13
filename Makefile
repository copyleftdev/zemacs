# ZEMACS Makefile

ZIG := zig
BIN_DIR := zig-out/bin
BINARY := $(BIN_DIR)/zemacs
CLIENT_SRC := clients/emacs/zemacs-client.el
CLIENT_DEST := $(HOME)/.emacs.d/lisp/zemacs-client.el

.PHONY: all build test clean install-emacs verify

all: build

build:
	$(ZIG) build

# Runs the internal unit tests
test:
	$(ZIG) build test

# Runs the functional integration verification (stdio pipe)
verify: build
	@echo "Verifying ZEMACS functional integration..."
	@printf '{"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "echo", "arguments": {"message": "Helo"}}}' > verify_input.json
	@cat verify_input.json | ./$(BINARY) | grep "Helo" && echo "Verification Passed: Stdout Transport" || echo "Verification Failed"
	@rm verify_input.json

# Installs the Emacs client configuration
# 1. Creates target directory if not exists
# 2. Copies the file
# 3. Updates the binary path in the file to the absolute path of the current build
install-emacs:
	@echo "Installing Emacs client..."
	@mkdir -p $(dir $(CLIENT_DEST))
	@cp $(CLIENT_SRC) $(CLIENT_DEST)
	@# Replace the placeholder or default path with the actual absolute path to the binary
	@sed -i 's|~/Project/zemacs/zig-out/bin/zemacs|$(shell pwd)/$(BINARY)|g' $(CLIENT_DEST)
	@echo "Installed to $(CLIENT_DEST)"
	@echo ""
	@echo "Add the following to your ~/.emacs or ~/.emacs.d/init.el:"
	@echo "  (add-to-list 'load-path \"$(dir $(CLIENT_DEST))\")"
	@echo "  (require 'zemacs-client)"

clean:
	rm -rf zig-out zig-cache
