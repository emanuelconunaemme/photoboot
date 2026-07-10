"""Photoboot print server.

Thin HTTP wrapper over CUPS. The iPad POSTs a strip image + the format it
wants printed; we route to one of two pre-configured CUPS queues.

Queues (created by deploy/bootstrap.sh):
  photoboot-4x6     — 4x6 media, no cut. Single 4x6 print per job.
  photoboot-strip   — 4x6 media, 2-cut. Printer cuts a 4x6 into two 2x6 strips.

Layout for the strip queue is handled server-side: when a single 2x6 image
(~1:3 aspect) is uploaded with format=2x6, the server duplicates it
side-by-side onto a fresh 4x6 sheet before queueing. iPad code is unaware
of the cutter and keeps its 2x6 composite as a single strip (so the same
image works for AirDrop/email/sharing).
"""

from __future__ import annotations

import logging
import os
import re
import tempfile
import time
from io import BytesIO
from pathlib import Path
from typing import Literal

import cups
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import JSONResponse
from PIL import Image

log = logging.getLogger("photoboot-print")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

QUEUES: dict[str, str] = {
    "4x6": "photoboot-4x6",
    "2x6": "photoboot-strip",
}

# Map CUPS printer-state-reasons → human-readable text the iPad surfaces.
# Reasons come tagged with a severity suffix (-error/-warning/-report);
# we strip the suffix and fall back to the base form if the exact string
# isn't in the table.
REASON_LABELS: dict[str, str] = {
    "media-empty":             "Out of paper",
    "media-low":               "Paper running low",
    "media-jam":               "Paper jam",
    "media-needed":            "Load paper",
    "marker-supply-empty":     "Out of ribbon",
    "marker-supply-low":       "Ribbon running low",
    "toner-empty":             "Out of ribbon",
    "toner-low":               "Ribbon running low",
    "developer-empty":         "Out of ribbon",
    "cover-open":              "Printer cover open",
    "door-open":               "Printer cover open",
    "input-tray-missing":      "Paper tray missing",
    "output-tray-missing":     "Output tray missing",
    "interlock-open":          "Printer interlock open",
    "offline":                 "Printer offline",
    "connecting-to-device":    "Connecting to printer",
    "timed-out":               "Printer not responding",
    "paused":                  "Print queue paused",
    "shutdown":                "Printer powered off",
    "stopped-partly":          "Printer paused",
    "spool-area-full":         "Server out of disk",
    "none":                    "",
}


def _label_for_reason(reason: str) -> str:
    """Translate a single printer-state-reason into a friendly string."""
    if reason in REASON_LABELS:
        return REASON_LABELS[reason]
    base = re.sub(r"-(error|warning|report)$", "", reason)
    if base in REASON_LABELS:
        return REASON_LABELS[base]
    return reason  # raw passthrough — better than silence


def _summarize_reasons(reasons) -> tuple[str, str]:
    """Return (severity, human_summary) for a list/tuple of CUPS reasons.

    Severity is one of: 'ok' | 'warning' | 'error'. The summary is the
    first non-empty labeled reason, or '' if everything's fine.
    """
    if isinstance(reasons, str):
        reasons = [reasons]
    reasons = [r for r in (reasons or []) if r and r != "none"]
    if not reasons:
        return "ok", ""
    severity = "warning"
    for r in reasons:
        if r.endswith("-error"):
            severity = "error"
            break
    labeled = next((s for s in (_label_for_reason(r) for r in reasons) if s), reasons[0])
    return severity, labeled


app = FastAPI(title="Photoboot Print Server", version="0.1.0")


def _layout_for_strip_queue(data: bytes) -> bytes:
    """Lay out a strip image so the DNP cutter produces two clean 2x6 strips.

    The cutter slices a 4x6 sheet down its long axis. So the input to the
    strip queue MUST be a 4x6 sheet with the strip duplicated side-by-side.
    Callers upload one of two shapes; we detect by aspect ratio:

      • ~1:3 portrait (e.g. 600x1800) — a single 2x6 strip. Each copy is
        shrunk ~2.5% and centered in its 2x6 half of the sheet so the
        DNP -div2 cutter's trim (a couple of mm on each side of the cut)
        lands in whitespace instead of eating into the design's inner
        edge. Result: both output strips have symmetric margins.
      • ~2:3 portrait OR ~3:2 landscape — assume the caller already laid
        out a 4x6 sheet; pass through unchanged.
    """
    img = Image.open(BytesIO(data))
    if img.mode != "RGB":
        img = img.convert("RGB")
    w, h = img.size
    # Normalize aspect to portrait (always treat as h ≥ w for the check).
    aspect = w / h
    if 0.28 <= aspect <= 0.40:
        # Symmetric layout: crop the same `gutter` px off both sides of
        # the design and place each cropped copy centered horizontally
        # in its 2x6 half of the sheet. Result: every output strip has
        # equal whitespace on its outer (paper) AND inner (cut) edges,
        # with no top/bottom whitespace. Each strip looks identical to
        # the other — no "one side has a white line, the other side is
        # cut too close" asymmetry.
        #
        # The design's own 24px of background-only padding around the
        # photos absorbs the crop; nothing that matters gets clipped.
        gutter = 15  # ~1.25mm at 300 DPI on outer and inner edges
        cropped = img.crop((gutter, 0, w - gutter, h))  # (w - 2*gutter) × h
        canvas = Image.new("RGB", (w * 2, h), (255, 255, 255))
        canvas.paste(cropped, (gutter, 0))
        canvas.paste(cropped, (w + gutter, 0))
        out = BytesIO()
        canvas.save(out, format="JPEG", quality=92, optimize=False)
        log.info(
            "laid out 2x6 strip %dx%d → 4x6 sheet %dx%d (gutter=%dpx per side)",
            w, h, w * 2, h, gutter,
        )
        return out.getvalue()
    # Already a 4x6 layout (either orientation) — pass through.
    return data


def _connect() -> cups.Connection:
    return cups.Connection()


def _inspect_queue(conn: cups.Connection, present: set[str], queue: str) -> dict:
    """Return a per-queue status dict, with a friendly summary string."""
    if queue not in present:
        return {
            "queue": queue,
            "present": False,
            "ready": False,
            "severity": "error",
            "summary": "Queue not configured",
            "reasons": [],
        }
    # getPrinters() on some CUPS builds omits printer-is-accepting-jobs;
    # getPrinterAttributes() returns the full attribute set per queue.
    attrs = conn.getPrinterAttributes(queue)
    # printer-state: 3=idle, 4=processing, 5=stopped
    state = attrs.get("printer-state", 0)
    accepting = bool(attrs.get("printer-is-accepting-jobs", False))
    raw_reasons = attrs.get("printer-state-reasons", []) or []
    severity, summary = _summarize_reasons(raw_reasons)
    if state == 5:
        severity = "error"
        if not summary:
            summary = "Printer stopped"
    elif not accepting:
        severity = "error"
        if not summary:
            summary = "Not accepting jobs"
    ready = state in (3, 4) and accepting and severity != "error"
    return {
        "queue": queue,
        "present": True,
        "state": state,
        "accepting": accepting,
        "ready": ready,
        "severity": severity,
        "summary": summary,
        "reasons": list(raw_reasons),
    }


@app.get("/health")
def health() -> JSONResponse:
    """Liveness + readiness in one shot.

    Returns 200 whenever the print *service* is alive. The `ok` field in
    the body answers the readiness question — false means the printer
    itself isn't ready (out of paper, ribbon, etc.). 503 is reserved for
    the case where the service can't reach CUPS at all.

    The iPad polls this to decide whether to surface the Print button:
    it checks `ok`, not the HTTP status, and reads `summary` for the
    user-facing reason.
    """
    try:
        conn = _connect()
        present = set(conn.getPrinters().keys())
    except Exception as exc:
        log.warning("cups connect failed: %s", exc)
        return JSONResponse(
            status_code=503,
            content={"ok": False, "summary": "Print service can't reach CUPS", "error": str(exc)},
        )

    queue_state = {fmt: _inspect_queue(conn, present, name) for fmt, name in QUEUES.items()}
    all_ready = all(q["ready"] for q in queue_state.values())
    if all_ready:
        summary = "Ready"
    else:
        # Surface the first non-empty queue summary. Every not-ready
        # path in _inspect_queue sets a summary, so this is just a
        # belt-and-braces fallback for unknown CUPS states.
        summary = next(
            (q["summary"] for q in queue_state.values() if q["summary"]),
            "Printer not ready",
        )

    return JSONResponse(
        status_code=200,
        content={"ok": all_ready, "summary": summary, "queues": queue_state},
    )


@app.post("/print")
async def submit_print(
    image: UploadFile = File(...),
    format: Literal["2x6", "4x6"] = Form(...),
    copies: int = Form(1),
) -> dict:
    queue = QUEUES[format]
    if copies < 1 or copies > 10:
        raise HTTPException(400, "copies must be 1..10")

    # Pre-flight: refuse to queue when the printer can't satisfy the job.
    # Without this, a job posted while the printer is out of paper sits
    # silently stalled and the iPad would see a happy 200 with a job id.
    conn = _connect()
    present = set(conn.getPrinters().keys())
    status = _inspect_queue(conn, present, queue)
    if not status["ready"]:
        raise HTTPException(
            status_code=503,
            detail={
                "summary": status["summary"] or "Printer not ready",
                "severity": status["severity"],
                "reasons": status["reasons"],
                "queue": queue,
            },
        )

    # Persist the upload to a temp file so CUPS can read it. CUPS spools
    # the data internally, so we can delete the file as soon as
    # printFile returns.
    #
    # For 2x6: lay out a 4x6 sheet with two strips side-by-side so the
    # printer's cutter produces two clean 2x6s. For 4x6: send as-is.
    body = await image.read()
    if format == "2x6":
        body = _layout_for_strip_queue(body)

    suffix = Path(image.filename or "strip.jpg").suffix or ".jpg"
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix, dir="/var/tmp")
    try:
        tmp.write(body)
        tmp.flush()
        tmp.close()

        options = {"copies": str(copies)}
        job_id = conn.printFile(queue, tmp.name, "photoboot", options)
        log.info("queued job=%s queue=%s bytes=%d copies=%d", job_id, queue, len(body), copies)
        return {"job_id": int(job_id), "queue": queue, "format": format, "copies": copies}
    finally:
        try:
            os.unlink(tmp.name)
        except OSError:
            pass


@app.get("/jobs/{job_id}")
def job_status(job_id: int) -> dict:
    conn = _connect()
    # which_jobs='all' includes completed; default is only active.
    jobs = conn.getJobs(which_jobs="all", requested_attributes=[
        "job-id", "job-name", "job-state", "job-state-reasons",
        "job-printer-uri", "job-k-octets",
    ])
    info = jobs.get(job_id)
    if not info:
        raise HTTPException(404, "job not found")
    return {"job_id": job_id, **{k: info.get(k) for k in info}}


@app.get("/")
def root() -> dict:
    return {
        "service": "photoboot-print",
        "version": app.version,
        "queues": QUEUES,
        "started_at": _STARTED_AT,
    }


_STARTED_AT = int(time.time())
