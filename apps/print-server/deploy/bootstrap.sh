#!/usr/bin/env bash
# Idempotent bootstrap for the Photoboot print server.
#
# Runs on the Ubuntu server as root (or via sudo). Re-running just
# upgrades — package installs are no-ops if up to date, lpadmin updates
# queues in place, systemctl daemon-reload picks up unit changes.
#
# Steps:
#   1. apt install CUPS, gutenprint, Avahi, Python + libcups2-dev for pycups.
#   2. Ensure 'photoboot' service account exists and is in the lp group.
#   3. Discover DNP DS-RX1HS USB URI + matching gutenprint PPD.
#   4. Create/update CUPS queues photoboot-4x6 and photoboot-strip.
#      photoboot-strip gets the 2-cut option so 4x6 media becomes two 2x6 strips.
#   5. Build/update the Python venv from requirements.txt.
#   6. Install systemd unit + Avahi service file. Reload, enable, start.

set -euo pipefail

APP_DIR="/opt/photoboot-print"
SERVICE_USER="photoboot"
SYSTEMD_UNIT="/etc/systemd/system/photoboot-print.service"
AVAHI_SERVICE="/etc/avahi/services/photoboot-print.service"

log() { printf '\033[1;36m[bootstrap]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[bootstrap] %s\033[0m\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "must run as root (use sudo)"

log "1/6 installing packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
  cups \
  cups-client \
  cups-bsd \
  printer-driver-gutenprint \
  avahi-daemon \
  python3-venv \
  python3-dev \
  libcups2-dev \
  build-essential \
  rsync \
  >/dev/null

systemctl enable --now cups.service avahi-daemon.service >/dev/null

log "2/6 ensuring '$SERVICE_USER' system user (member of lp)"
if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
  useradd --system --home "$APP_DIR" --shell /usr/sbin/nologin "$SERVICE_USER"
fi
usermod -a -G lp "$SERVICE_USER"
chown -R "$SERVICE_USER:$SERVICE_USER" "$APP_DIR"

log "3/6 discovering DS-RX1HS USB URI + PPD"
# lpinfo -v emits one URI per line, e.g.:
#   direct gutenprint53+usb://dnp-dsrx1/CB2D5A201835
#   direct usb://DNP/DS-RX1?serial=...
# Match case-insensitively on either the bare usb:// or the gutenprint+usb
# scheme, and any of the variant model spellings.
PRINTER_URI="$(lpinfo -v 2>/dev/null | grep -iE 'usb://.*(dnp|ds-?rx1|dsrx1|citizen)' | head -1 | awk '{print $2}' || true)"
[[ -n "$PRINTER_URI" ]] || die "no DNP/RX1 USB device detected — is the printer plugged in and powered on?"
log "    URI: $PRINTER_URI"

# lpinfo -m emits one PPD per line, e.g.:
#   gutenprint.5.3://dnp-dsrx1/expert  Dai Nippon Printing DSRX1 - CUPS+Gutenprint v5.3.4
# Gutenprint 5.3 ships one entry for the whole DS-RX1 family (covers the HS).
PPD_KEY="$(lpinfo -m 2>/dev/null | grep -iE '(dnp|dai nippon).*rx1' | head -1 | awk '{print $1}' || true)"
[[ -n "$PPD_KEY" ]] || die "no gutenprint PPD matching DNP RX1 — is printer-driver-gutenprint installed?"
log "    PPD: $PPD_KEY"

create_queue() {
  local name="$1"; shift
  local page_size="$1"; shift
  local extra_opts=("$@")
  log "    queue: $name (PageSize=$page_size)"
  # Gutenprint for DNP encodes the cutter mode *inside* PageSize:
  #   w288h432       — 4x6 single sheet, no cut
  #   w288h432-div2  — 4x6 cut into two 2x6 strips
  # There is no separate StpMultiCut/Cutter option — discovered by dumping
  # `lpoptions -p <queue> -l` on a fresh setup.
  #
  # printer-error-policy=abort-job: when a job fails (e.g. out of paper)
  # CUPS aborts that job but keeps the queue accepting future ones. The
  # default 'stop-printer' policy silently disables the queue on failure,
  # which is the wrong shape for an unattended kiosk — the iPad would
  # show "Printer not ready" with no obvious recovery path. With abort-job
  # the iPad simply re-shows the Print button once consumables are loaded.
  lpadmin -p "$name" -E -v "$PRINTER_URI" -m "$PPD_KEY" \
    -o printer-is-shared=true \
    -o printer-error-policy=abort-job \
    -o PageSize="$page_size" \
    -o StpImageType=Photo \
    "${extra_opts[@]}"
  # Re-arm in case a previous run left the queue stopped/rejecting due
  # to the old default error policy. These are idempotent.
  cupsenable "$name" >/dev/null
  cupsaccept "$name" >/dev/null
}

log "4/6 creating CUPS queues"
# 4x6 queue: full sheet, no cut.
create_queue "photoboot-4x6" "w288h432"
# 2x6 strip queue: 4x6 media cut into two 2x6 strips. StpNoCutWaste=True
# closes the unprinted gap between strips so each strip is full-bleed.
create_queue "photoboot-strip" "w288h432-div2" -o StpNoCutWaste=True

# Dump key effective options for the strip queue — useful first-deploy
# diagnostic. grep reads stdin fully so it can't SIGPIPE upstream, which
# `head` would (and pipefail then propagates as exit 141).
log "    photoboot-strip key options:"
lpoptions -p photoboot-strip -l \
  | grep -E '^(PageSize|ColorModel|Resolution|StpImageType|StpLaminate|StpNoCutWaste)/' \
  | sed 's/^/      /'

log "5/6 building Python venv"
sudo -u "$SERVICE_USER" python3 -m venv "$APP_DIR/.venv"
sudo -u "$SERVICE_USER" "$APP_DIR/.venv/bin/pip" install --quiet --upgrade pip
sudo -u "$SERVICE_USER" "$APP_DIR/.venv/bin/pip" install --quiet -r "$APP_DIR/requirements.txt"

log "6/6 installing systemd + Avahi service files"
install -m 644 "$APP_DIR/deploy/photoboot-print.service" "$SYSTEMD_UNIT"
install -m 644 "$APP_DIR/deploy/photoboot-print.avahi.service" "$AVAHI_SERVICE"
systemctl daemon-reload
systemctl enable --now photoboot-print.service >/dev/null
systemctl restart photoboot-print.service

# Wait a beat, then sanity-check the service is up.
sleep 1
if systemctl is-active --quiet photoboot-print.service; then
  log "✅ photoboot-print is running on port 8787"
else
  systemctl --no-pager --full status photoboot-print.service || true
  die "service failed to start"
fi

log "done. Test:  curl -s http://$(hostname).local:8787/health | jq"
