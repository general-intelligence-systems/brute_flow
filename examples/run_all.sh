#!/bin/bash
set -e
cd "$(dirname "$0")/.."

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass=0
fail=0

run_example() {
  local name=$(basename "$1" .rb)
  printf "RUN  %s... " "$name"
  if bundle exec ruby "$1" > /dev/null 2>&1; then
    printf "${GREEN}PASS${NC}\n"
    pass=$((pass + 1))
  else
    printf "${RED}FAIL${NC}\n"
    fail=$((fail + 1))
    bundle exec ruby "$1" 2>&1 | tail -5 | sed 's/^/     /'
  fi
}

echo "=== Brute Flow Examples ==="
echo

run_example examples/01_flow_builder.rb
run_example examples/02_flow_runner.rb

echo
echo "=== $pass passed, $fail failed ==="
[ $fail -eq 0 ] || exit 1
