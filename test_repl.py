import subprocess
import json
import time

BINARY = "./zig-out/bin/zemacs"

def rpc(proc, method, params=None, req_id=1):
    req = {
        "jsonrpc": "2.0",
        "id": req_id,
        "method": method,
        "params": params or {}
    }
    json_str = json.dumps(req)
    proc.stdin.write(json_str.encode() + b"\n")
    proc.stdin.flush()
    
    line = proc.stdout.readline()
    if not line:
        return None
    return json.loads(line)

def run_test():
    print("Starting ZEMACS for REPL Test...")
    proc = subprocess.Popen(
        [BINARY],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,  # Capture stderr to avoid clutter
        bufsize=0  # Unbuffered
    )

    try:
        # 1. Start Python REPL
        print("1. Starting Python REPL...")
        res = rpc(proc, "tools/call", {
            "name": "repl.start",
            "arguments": {"command": "python3 -i"}
        }, 1)
        # The result logic in ZEMACS repl.start returns a simple integer ID.
        print(f"Debug Result: {res['result']}")
        if isinstance(res['result'], int):
            repl_id = res['result']
        else:
            # Fallback for structured content (if schema evolves)
            repl_id = int(res['result'])
            
        print(f"   REPL ID: {repl_id}")

        # 2. Define Variable (State)
        print("2. Defining Variable 'x = 1337'...")
        rpc(proc, "tools/call", {
            "name": "repl.eval",
            "arguments": {"id": repl_id, "code": "x = 1337"}
        }, 2)
        
        # Give it a moment to process
        time.sleep(0.5)

        # 3. Read Output (Should see python prompt or empty)
        res = rpc(proc, "tools/call", {
            "name": "repl.read",
            "arguments": {"id": repl_id}
        }, 3)
        print(f"   Read 1: {res['result']}")

        # 4. Print Variable
        print("3. Printing Variable 'print(x)'...")
        rpc(proc, "tools/call", {
            "name": "repl.eval",
            "arguments": {"id": repl_id, "code": "print(x)"}
        }, 4)
        
        time.sleep(0.5)

        # 5. Read Output (Should see '1337')
        res = rpc(proc, "tools/call", {
            "name": "repl.read",
            "arguments": {"id": repl_id}
        }, 5)
        stdout = res['result']['stdout']
        print(f"   Read 2: {stdout.strip()}")

        if "1337" in stdout:
            print("SUCCESS: State persisted.")
        else:
            print("FAILURE: Did not find 1337 in output.")
            exit(1)

        # 6. Kill
        print("4. Killing REPL...")
        rpc(proc, "tools/call", {
            "name": "repl.kill",
            "arguments": {"id": repl_id}
        }, 6)
        
        print("Test Passed.")

    except Exception as e:
        print(f"Error: {e}")
        # kill proc
        proc.kill()
        exit(1)
    
    proc.terminate()

if __name__ == "__main__":
    run_test()
