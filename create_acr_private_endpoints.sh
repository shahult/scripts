#!/bin/bash
# ============================================================
# create_acr_private_endpoints.sh
# Creates private endpoints for Azure Container Registries
# defined in a CSV file.
#
# CSV Format (with header row):
#   acr_name,acr_resource_group,source_subscription_id,dest_resource_group_id,dns_zone_id,subnet_id
#
# Usage:
#   ./create_acr_private_endpoints.sh --csv acr_list.csv
#   ./create_acr_private_endpoints.sh --csv acr_list.csv --dry-run
# ============================================================

set -euo pipefail

LOCATION="switzerlandnorth"
LOG_FILE="acr_pe_$(date +%Y%m%d_%H%M%S).log"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

log()  { echo -e "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
ok()   { log "${GREEN}[OK]${NC}    $*"; }
warn() { log "${YELLOW}[WARN]${NC}  $*"; }
err()  { log "${RED}[ERROR]${NC} $*"; }

usage() {
  cat <<EOF
Usage: $0 --csv <file> [--dry-run]

Required:
  --csv      Path to the CSV file

CSV columns (with header):
  acr_name               Name of the Azure Container Registry
  acr_resource_group     Resource group where the ACR lives
  source_subscription_id Subscription ID of the ACR
  dest_resource_group_id Full resource ID of the destination RG for the private endpoint
  dns_zone_id            Full resource ID of the Private DNS Zone
  subnet_id              Full resource ID of the subnet for the private endpoint

Optional:
  --dry-run  Print commands without executing them
  -h|--help  Show this help
EOF
  exit 0
}

CSV_FILE=""; DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --csv)     CSV_FILE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true;  shift   ;;
    -h|--help) usage ;;
    *) err "Unknown argument: $1"; usage ;;
  esac
done

[[ -z "$CSV_FILE" ]] && { err "--csv is required."; usage; }
[[ -f "$CSV_FILE" ]] || { err "CSV file not found: $CSV_FILE"; exit 1; }

run() {
  if $DRY_RUN; then
    log "[DRY-RUN] $*"
  else
    eval "$@"
  fi
}

log "======================================================"
log " ACR Private Endpoint Creation Script"
log "======================================================"
log " CSV file : $CSV_FILE"
log " Location : $LOCATION"
log " Dry run  : $DRY_RUN"
log "======================================================"

TOTAL=0; SUCCESS=0; FAILED=0

# Read CSV — skip header, skip blank/comment lines, strip Windows line endings
tail -n +2 "$CSV_FILE" | tr -d '\r' | while IFS=',' read -r ACR_NAME ACR_RG SOURCE_SUB DEST_RG_ID DNS_ZONE_ID SUBNET_ID; do

  [[ -z "$ACR_NAME" || "$ACR_NAME" == \#* ]] && continue

  # Trim whitespace from all fields
  ACR_NAME=$(echo "$ACR_NAME"       | xargs)
  ACR_RG=$(echo "$ACR_RG"           | xargs)
  SOURCE_SUB=$(echo "$SOURCE_SUB"   | xargs)
  DEST_RG_ID=$(echo "$DEST_RG_ID"   | xargs)
  DNS_ZONE_ID=$(echo "$DNS_ZONE_ID" | xargs)
  SUBNET_ID=$(echo "$SUBNET_ID"     | xargs)

  # Validate all fields are present
  MISSING=()
  [[ -z "$ACR_NAME"    ]] && MISSING+=("acr_name")
  [[ -z "$ACR_RG"      ]] && MISSING+=("acr_resource_group")
  [[ -z "$SOURCE_SUB"  ]] && MISSING+=("source_subscription_id")
  [[ -z "$DEST_RG_ID"  ]] && MISSING+=("dest_resource_group_id")
  [[ -z "$DNS_ZONE_ID" ]] && MISSING+=("dns_zone_id")
  [[ -z "$SUBNET_ID"   ]] && MISSING+=("subnet_id")

  if [[ ${#MISSING[@]} -gt 0 ]]; then
    err "Row $((TOTAL+1)): Missing fields: ${MISSING[*]} — skipping."
    FAILED=$((FAILED + 1))
    TOTAL=$((TOTAL + 1))
    continue
  fi

  TOTAL=$((TOTAL + 1))

  # Derive names and IDs
  DEST_RG_NAME=$(basename "$DEST_RG_ID")
  DEST_SUB=$(echo "$DEST_RG_ID" | cut -d'/' -f3)
  ACR_ID="/subscriptions/${SOURCE_SUB}/resourceGroups/${ACR_RG}/providers/Microsoft.ContainerRegistry/registries/${ACR_NAME}"
  PE_NAME="pe-${ACR_NAME}"
  CONN_NAME="conn-${ACR_NAME}"
  DNS_GROUP_NAME="dzg-${ACR_NAME}"

  log "------------------------------------------------------"
  log "[$TOTAL] ACR     : $ACR_NAME"
  log "      ACR RG   : $ACR_RG  (sub: $SOURCE_SUB)"
  log "      Dest RG  : $DEST_RG_NAME  (sub: $DEST_SUB)"
  log "      DNS Zone : $DNS_ZONE_ID"
  log "      Subnet   : $SUBNET_ID"

  # Step 1 — Switch to destination subscription
  log "  [1/4] Setting subscription to $DEST_SUB ..."
  if ! run "az account set --subscription '$DEST_SUB'"; then
    err "  Failed to set subscription. Skipping $ACR_NAME."
    FAILED=$((FAILED + 1)); continue
  fi

  # Step 2 — Ensure destination resource group exists
  log "  [2/4] Ensuring resource group '$DEST_RG_NAME' exists ..."
  run "az group show --name '$DEST_RG_NAME' --output none 2>/dev/null || \
    az group create --name '$DEST_RG_NAME' --location '$LOCATION' --output none"

  # Step 3 — Create private endpoint
  log "  [3/4] Creating private endpoint '$PE_NAME' ..."
  if ! run "az network private-endpoint create \
      --name '$PE_NAME' \
      --resource-group '$DEST_RG_NAME' \
      --location '$LOCATION' \
      --subnet '$SUBNET_ID' \
      --private-connection-resource-id '$ACR_ID' \
      --group-id 'registry' \
      --connection-name '$CONN_NAME' \
      --output none"; then
    err "  Failed to create private endpoint for $ACR_NAME."
    FAILED=$((FAILED + 1)); continue
  fi
  ok "  Private endpoint '$PE_NAME' created."

  # Step 4 — Create DNS zone group
  log "  [4/4] Creating DNS zone group '$DNS_GROUP_NAME' ..."
  if ! run "az network private-endpoint dns-zone-group create \
      --name '$DNS_GROUP_NAME' \
      --resource-group '$DEST_RG_NAME' \
      --endpoint-name '$PE_NAME' \
      --private-dns-zone '$DNS_ZONE_ID' \
      --zone-name 'privatelink.azurecr.io' \
      --output none"; then
    err "  Failed to create DNS zone group for $ACR_NAME."
    FAILED=$((FAILED + 1)); continue
  fi
  ok "  DNS zone group '$DNS_GROUP_NAME' created."

  SUCCESS=$((SUCCESS + 1))
  ok "  ✔ Completed: $ACR_NAME"

done

log "======================================================"
log " Summary"
log "======================================================"
log "  Total     : $TOTAL"
ok  "  Succeeded : $SUCCESS"
[[ $FAILED -gt 0 ]] && err "  Failed    : $FAILED" || log "  Failed    : 0"
log "  Log file  : $LOG_FILE"
log "======================================================"
