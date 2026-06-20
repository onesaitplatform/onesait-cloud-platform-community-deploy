"""
Patch script: fixes MLflow 3.x search_experiments rejecting max_results=0.

When the Onesait Platform CP sends an empty JSON body {} to
POST /api/2.0/mlflow/experiments/search, protobuf deserialises
max_results as 0 (int default). MLflow 3.x validates max_results >= 1
and returns 400. This script patches the handler to treat 0 as 1000.

Run once at container startup (added to docker-entrypoint.sh) or during
Docker image build.
"""
import re, sys

TARGET = "/usr/local/lib/python3.12/site-packages/mlflow/server/handlers.py"

with open(TARGET, "r") as f:
    src = f.read()

OLD = "max_results=request_message.max_results,"
NEW = "max_results=request_message.max_results or 1000,"

if NEW in src:
    print("handlers.py already patched — skipping")
    sys.exit(0)

if OLD not in src:
    print(f"ERROR: expected string not found in {TARGET}", file=sys.stderr)
    sys.exit(1)

patched = src.replace(OLD, NEW)
with open(TARGET, "w") as f:
    f.write(patched)

print(f"handlers.py patched: {src.count(OLD)} occurrence(s) replaced")
