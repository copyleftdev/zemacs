import subprocess
import random
import os
import sys
import time

HARNESS = "./zemacs-fuzz"
ITERATIONS = 5000
CRASHES_DIR = "crashes"

def generate_garbage(length):
    return os.urandom(length)

def generate_json_garbage():
    # Somewhat valid-looking JSON but broken
    chars = b"{}\"':,[]0123456789abcdef"
    length = random.randint(10, 1000)
    return bytes(random.choice(chars) for _ in range(length))

def run_fuzz():
    if not os.path.exists(CRASHES_DIR):
        os.makedirs(CRASHES_DIR)

    print(f"Starting Fuzzing Campaign: {ITERATIONS} iterations...")
    crashes = 0
    start_time = time.time()

    for i in range(ITERATIONS):
        # Mix of strategies
        rand = random.random()
        if rand < 0.5:
            data = generate_garbage(random.randint(1, 1024))
        elif rand < 0.9:
            data = generate_json_garbage()
        else:
            data = b"" # Edge case: empty

        process = subprocess.Popen(
            [HARNESS], 
            stdin=subprocess.PIPE, 
            stdout=subprocess.DEVNULL, 
            stderr=subprocess.DEVNULL
        )
        try:
            process.communicate(input=data, timeout=1)
        except subprocess.TimeoutExpired:
            process.kill()
            print(f"TIMEOUT on input size {len(data)}")
            # Timeouts are technically failures too for performance, saving them
            with open(f"{CRASHES_DIR}/timeout_{i}.bin", "wb") as f:
                f.write(data)
            crashes += 1
            continue

        if process.returncode != 0:
            print(f"CRASH detected! Return code: {process.returncode}")
            with open(f"{CRASHES_DIR}/crash_{i}.bin", "wb") as f:
                f.write(data)
            crashes += 1

        if i % 1000 == 0:
            print(f"Completed {i} iterations...")

    elapsed = time.time() - start_time
    print(f"Fuzzing Complete in {elapsed:.2f}s")
    print(f"Total Crashes: {crashes}")

    if crashes == 0:
        print("SUCCESS: No crashes found.")
        sys.exit(0)
    else:
        print("FAILURE: Crashes detected.")
        sys.exit(1)

if __name__ == "__main__":
    run_fuzz()
