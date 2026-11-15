#!/usr/bin/env bash
# Validate loop for one lab directory: fmt -> init -> validate -> plan (never apply).
# Usage: validate.sh <lab-dir>
# Exit 0 = all steps passed. Prints a one-line summary per step, then the plan summary.
set -uo pipefail

lab="${1:?usage: validate.sh <lab-dir>}"
cd "$lab" || { echo "FAIL  no such dir: $lab"; exit 2; }

status=0
step() { # step <name> <cmd...>
  local name="$1"; shift
  local out
  if out="$("$@" 2>&1)"; then
    echo "PASS  $name"
  else
    echo "FAIL  $name"
    echo "$out" | tail -40 | sed 's/^/      /'
    status=1
  fi
}

# fmt rewrites files in place; list what it changed so the caller can review and commit it.
changed="$(tofu fmt -recursive 2>&1)"
if [ -n "$changed" ]; then echo "FIXED fmt (reformatted: $(echo "$changed" | tr '\n' ' '))"; else echo "PASS  fmt"; fi

if [ ! -d .terraform ]; then step init tofu init -input=false; fi
step validate tofu validate -no-color
[ "$status" -ne 0 ] && exit "$status"

# Plan needs Azure auth (az login) and, for kubectl_manifest resources, a reachable cluster.
plan_out="$(tofu plan -input=false -no-color -out=tfplan 2>&1)"
if [ $? -eq 0 ]; then
  echo "PASS  plan"
  echo "$plan_out" | grep -E '^(Plan:|No changes\.)' | sed 's/^/      /'
  # Replacements/destroys are the expensive surprises (e.g. recreating the AKS cluster).
  echo "$plan_out" | grep -E 'must be replaced|will be destroyed' | sed 's/^/      WARN /'
elif echo "$plan_out" | grep -q 'kubectl provider: configure failed'; then
  # Cluster not running (e.g. destroyed to save cost): the kubectl provider can't be
  # configured. Fall back to planning only the azurerm resources so they're still checked.
  targets="$(grep -hoE '^resource "azurerm_[a-z_]+" "[A-Za-z0-9_-]+"' *.tf \
    | awk '{gsub(/"/,""); print "-target=" $2 "." $3}')"
  # shellcheck disable=SC2086
  plan_out="$(tofu plan -input=false -no-color -out=tfplan $targets 2>&1)"
  if [ $? -eq 0 ]; then
    echo "PARTIAL plan (cluster unreachable: azurerm resources only, kubectl_manifest resources not planned)"
    echo "$plan_out" | grep -E '^(Plan:|No changes\.)' | sed 's/^/      /'
    echo "$plan_out" | grep -E 'must be replaced|will be destroyed' | sed 's/^/      WARN /'
  else
    echo "FAIL  plan (targeted azurerm-only fallback)"
    echo "$plan_out" | grep -E -A8 '^(│ )?Error' | head -60 | sed 's/^/      /'
    status=1
  fi
else
  echo "FAIL  plan"
  echo "$plan_out" | grep -E -A8 '^(│ )?Error' | head -60 | sed 's/^/      /'
  status=1
fi

exit "$status"
