#!/bin/bash
# Provision a fx3-cmix work VM.
# Usage: ./provision.sh <name> [--spot] [--size Standard_D4ds_v4]
# Then:  ssh hutter@<ip>  and run  infra/setup.sh
set -euo pipefail

NAME="${1:?usage: provision.sh <name> [--spot] [--size SIZE]}"; shift || true
SIZE="Standard_D4ds_v4"
SPOT_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --spot) SPOT_ARGS=(--priority Spot --eviction-policy Deallocate --max-price -1);;
    --size) shift; SIZE="$1";;
  esac
  shift
done

# centralus + westcentralus: the two regions offering v3/v4 SKUs to this student
# subscription (eastus/westus2/etc return NotAvailableForSubscription). Quotas are
# PER-REGION (6 on-demand + 3 spot vCPUs each) — override LOC to tap the second pool.
LOC="${LOC:-centralus}"
RG="${RG:-hutter-lab}"   # use a region-local RG (e.g. RG=hutter-wcus) when LOC != centralus

az group create -n $RG -l $LOC -o none

az vm create -g $RG -n "$NAME" \
  --location $LOC \
  --image Ubuntu2204 \
  --size "$SIZE" \
  --admin-username hutter \
  --ssh-key-values ~/.ssh/id_ed25519.pub \
  --os-disk-size-gb 30 \
  --storage-sku StandardSSD_LRS \
  --public-ip-sku Standard \
  --nic-delete-option Delete \
  --os-disk-delete-option Delete \
  ${SPOT_ARGS[@]+"${SPOT_ARGS[@]}"} \
  --query '{name:name, ip:publicIpAddress}' -o table

# Safety net: daily auto-shutdown at 09:00 UTC (4/5am ET). Deallocate manually
# when idle: az vm deallocate -g hutter-lab -n <name>
az vm auto-shutdown -g $RG -n "$NAME" --time 0900 -o none
echo "auto-shutdown set to 09:00 UTC"
