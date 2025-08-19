import os
import re
import shlex
import json
from datetime import datetime
import subprocess
from pathlib import Path

from flask import Flask, render_template, request, redirect, url_for, flash, Response, send_from_directory, send_file, after_this_request


app = Flask(__name__)
app.secret_key = os.environ.get("FLASK_SECRET_KEY", "pipe-secret")


def get_env_with_cargo_path():
    env = os.environ.copy()
    cargo_bin = str(Path.home() / ".cargo" / "bin")
    env["PATH"] = f"{cargo_bin}:{env.get('PATH', '')}"
    return env


def run_command(cmd, timeout=600, cwd=None):
    try:
        completed = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            env=get_env_with_cargo_path(),
            cwd=cwd,
        )
        return completed.returncode, completed.stdout, completed.stderr
    except subprocess.TimeoutExpired as exc:
        return 124, exc.stdout or "", exc.stderr or ""


def ensure_uploads_dir() -> Path:
    uploads = Path.home() / "uploads"
    uploads.mkdir(parents=True, exist_ok=True)
    return uploads


def ensure_downloads_dir() -> Path:
    downloads = Path.home() / "downloads"
    downloads.mkdir(parents=True, exist_ok=True)
    return downloads


def parse_public_links(output: str):
    # Try to extract well-formed direct and preview links from CLI output, including cases
    # where only the hash is present in text. If only preview has a full URL, derive direct.
    direct = None
    preview = None
    base_url = None
    found_hash = None
    for raw in output.splitlines():
        line = raw.strip()
        if not line:
            continue
        # Full URL first
        m_full = re.search(r"https?://\S*publicDownload\?hash=([A-Za-z0-9]+)(?:&preview=true)?", line)
        if m_full:
            url = m_full.group(0)
            h = m_full.group(1)
            found_hash = found_hash or h
            b = url.split('/publicDownload')[0]
            base_url = base_url or b
            if 'preview=true' in url:
                preview = url
            else:
                direct = url
            continue
        # Hash-only reference
        m_hash = re.search(r"publicDownload\?hash=([A-Za-z0-9]+)", line)
        if m_hash:
            found_hash = found_hash or m_hash.group(1)
    if base_url and found_hash:
        if not direct:
            direct = f"{base_url}/publicDownload?hash={found_hash}"
        if not preview:
            preview = f"{base_url}/publicDownload?hash={found_hash}&preview=true"
    return direct, preview


def get_token_usage():
    code, out, err = run_command(["pipe", "token-usage"])  # defaults to 30d
    if code != 0:
        return False, err.strip() or out.strip() or "Failed to fetch token usage."
    return True, out


def list_uploaded_files():
    code, out, err = run_command(["pipe", "list-uploads"])
    if code != 0:
        return []
    names = []
    # Example line: 1: local='./5cm.mkv', remote='5cm.mkv', status='SUCCESS', msg='...'
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        # Prefer entries that show SUCCESS, but accept any
        m = re.search(r"remote='([^']+)'", line)
        if m:
            remote_name = m.group(1)
            names.append(remote_name)
    # De-duplicate while preserving order
    seen = set()
    unique = []
    for n in names:
        if n not in seen:
            unique.append(n)
            seen.add(n)
    return unique


def get_base_dir() -> Path:
    base = os.environ.get("PIPE_BASE_DIR")
    if base:
        return Path(base)
    return Path.home() / "Pipe-Firestarter-Storage-Node"


def get_history_path() -> Path:
    base_dir = get_base_dir()
    base_dir.mkdir(parents=True, exist_ok=True)
    return base_dir / "public_links.json"


def load_public_links_history():
    path = get_history_path()
    if not path.exists():
        return []
    try:
        with path.open("r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, list):
            return data
    except Exception:
        pass
    return []


def append_public_link_history(file_name: str, direct: str | None, preview: str | None):
    if not (direct or preview):
        return
    path = get_history_path()
    hist = load_public_links_history()
    hist.append({
        "file": file_name,
        "direct": direct,
        "preview": preview,
        "ts": datetime.utcnow().isoformat() + "Z",
    })
    # keep last 50
    hist = hist[-50:]
    try:
        with path.open("w", encoding="utf-8") as f:
            json.dump(hist, f, ensure_ascii=False, indent=2)
    except Exception:
        pass


@app.route("/", methods=["GET"])
def index():
    # Show forms and any recent uploads to help users pick file names quickly
    uploads = list_uploaded_files()
    history = load_public_links_history()
    # newest first for display
    history = list(reversed(history))
    return render_template("index.html", uploads=uploads, link_history=history)


@app.post("/deposit")
def deposit():
    amount = (request.form.get("amount") or "").strip()
    if not amount:
        flash("Enter an amount in SOL.", "error")
        return redirect(url_for("index"))
    # basic validation: numeric
    if not re.fullmatch(r"\d+(?:\.\d+)?", amount):
        flash("Amount must be a number.", "error")
        return redirect(url_for("index"))

    code, out, err = run_command(["pipe", "swap-sol-for-pipe", amount])
    if code == 0:
        flash(f"Swap submitted for {amount} SOL. Output:\n{out}", "success")
    else:
        flash(f"Swap failed. Error:\n{err or out}", "error")
    return redirect(url_for("index"))


@app.post("/upload_local")
def upload_local():
    ensure_uploads_dir()
    file = request.files.get("file")
    desired_name = (request.form.get("desired_name") or "").strip()
    if not file or file.filename == "":
        flash("Please choose a file to upload.", "error")
        return redirect(url_for("index"))
    # If custom name provided, use that for remote name; still save locally with original name
    saved_path = ensure_uploads_dir() / file.filename
    file.save(saved_path)

    # Remote name: prefer custom name if provided, else original filename
    file_name = desired_name if desired_name else file.filename
    code, out, err = run_command(["pipe", "upload-file", str(saved_path), file_name])
    if code == 0:
        flash(f"Uploaded '{file_name}'. CLI output:\n{out}", "success")
    else:
        flash(f"Upload failed. Error:\n{err or out}", "error")
    return redirect(url_for("index"))


@app.post("/upload_gdrive")
def upload_gdrive():
    uploads_dir = ensure_uploads_dir()
    url = (request.form.get("gdrive_url") or "").strip()
    desired_name = (request.form.get("desired_name_g") or "").strip()
    if not url:
        flash("Provide a Google Drive URL.", "error")
        return redirect(url_for("index"))

    if desired_name:
        # Save with the provided name
        output_name = desired_name
        output_path = uploads_dir / output_name
        code, out, err = run_command(["gdown", "--fuzzy", url, "-O", str(output_path)], timeout=10800)
        if code != 0:
            flash(f"Download failed. Error:\n{err or out}", "error")
            return redirect(url_for("index"))
    else:
        # Let gdown use the original filename; download into uploads_dir
        before = {p.name for p in uploads_dir.iterdir()} if uploads_dir.exists() else set()
        code, out, err = run_command(["gdown", "--fuzzy", url], cwd=str(uploads_dir), timeout=10800)
        if code != 0:
            flash(f"Download failed. Error:\n{err or out}", "error")
            return redirect(url_for("index"))
        after = {p.name for p in uploads_dir.iterdir()} if uploads_dir.exists() else set()
        created = list(after - before)
        if len(created) == 1:
            output_name = created[0]
        else:
            # Fallback: pick most recently modified file in uploads_dir
            try:
                latest = max(uploads_dir.iterdir(), key=lambda p: p.stat().st_mtime)
                output_name = latest.name
            except ValueError:
                output_name = "downloaded_file"
        output_path = uploads_dir / output_name

    code2, out2, err2 = run_command(["pipe", "upload-file", str(output_path), output_name])
    if code2 == 0:
        flash(f"Downloaded and uploaded '{output_name}'. CLI output:\n{out2}", "success")
    else:
        flash(f"Upload failed after download. Error:\n{err2 or out2}", "error")
    return redirect(url_for("index"))


@app.get("/referrals")
def referrals():
    code, out, err = run_command(["pipe", "referral", "show"], timeout=120)
    if code == 0:
        flash(out or "(no output)", "success")
    else:
        flash(err or out or "Failed to fetch referral stats.", "error")
    return redirect(url_for("index"))


@app.post("/download")
def download():
    # Prefer manual name if provided, else use the selection
    remote_manual = (request.form.get("remote_name_manual") or "").strip()
    remote_select = (request.form.get("remote_name_select") or "").strip()
    remote = remote_manual or remote_select
    local = (request.form.get("local_name") or "").strip()
    legacy = request.form.get("legacy") == "on"

    if not remote:
        flash("Select or enter a remote file name.", "error")
        return redirect(url_for("index"))
    if not local:
        # Auto-derive a reasonable filename for the client
        local = remote if "." in remote else f"{remote}.bin"

    downloads = ensure_downloads_dir()
    target = downloads / local
    cmd = ["pipe", "download-file", remote, str(target)]
    if legacy:
        cmd.append("--legacy")
    code, out, err = run_command(cmd, timeout=10800)
    if code != 0:
        flash(err or out or "Download failed.", "error")
        return redirect(url_for("index"))

    @after_this_request
    def _cleanup(response):
        try:
            target.unlink(missing_ok=True)  # type: ignore[arg-type]
        except Exception:
            pass
        return response

    # Immediately return the file to the user's browser as a download
    return send_file(
        str(target),
        as_attachment=True,
        download_name=local,
        mimetype="application/octet-stream",
        max_age=0,
    )


@app.get("/files/downloads/<path:filename>")
def serve_download(filename: str):
    directory = str(ensure_downloads_dir())
    # as_attachment=True forces a browser download
    return send_from_directory(directory, filename, as_attachment=True)


@app.post("/public_link")
def public_link():
    # Accept from dropdown or manual text field; manual overrides if present
    manual = (request.form.get("public_file_name_manual") or "").strip()
    selected = (request.form.get("public_file_name") or "").strip()
    file_name = manual or selected
    if not file_name:
        flash("Enter the file name you used when uploading.", "error")
        return redirect(url_for("index"))

    code, out, err = run_command(["pipe", "create-public-link", file_name])
    if code != 0:
        flash(f"Failed to create public link. Error:\n{err or out}", "error")
        return redirect(url_for("index"))

    direct, preview = parse_public_links(out)
    if direct or preview:
        combined = "\n".join(filter(None, [
            "Direct link (for downloads/playback):",
            direct,
            "",
            "Social media link (for sharing):",
            preview,
        ]))
        flash(combined, "success")
        append_public_link_history(file_name, direct, preview)
    else:
        flash(out, "success")
    return redirect(url_for("index"))


@app.get("/usage")
def usage():
    ok, data = get_token_usage()
    if ok:
        flash(data, "success")
    else:
        flash(data, "error")
    return redirect(url_for("index"))


def is_allowed_command(cmd_text: str) -> bool:
    try:
        tokens = shlex.split(cmd_text)
    except Exception:
        return False
    if not tokens:
        return False
    # Allow only pipe commands by default
    return tokens[0] == "pipe"


@app.post("/run")
def run_cmd():
    cmd_text = (request.form.get("cmd") or "").strip()
    if not cmd_text:
        flash("Enter a command to run.", "error")
        return redirect(url_for("index"))
    if not is_allowed_command(cmd_text):
        flash("Only pipe commands are allowed here.", "error")
        return redirect(url_for("index"))
    try:
        tokens = shlex.split(cmd_text)
    except Exception:
        flash("Could not parse your command.", "error")
        return redirect(url_for("index"))
    code, out, err = run_command(tokens, timeout=120)
    banner = f"$ {cmd_text}\n"
    if code == 0:
        flash(banner + (out or "(no output)"), "success")
    else:
        flash(banner + (err or out or "Command failed."), "error")
    return redirect(url_for("index"))


@app.post("/quick/list-uploads")
def quick_list_uploads():
    code, out, err = run_command(["pipe", "list-uploads"], timeout=60)
    if code == 0:
        flash(out or "(no output)", "success")
    else:
        flash(err or out or "Failed to list uploads.", "error")
    return redirect(url_for("index"))


if __name__ == "__main__":
    # Development server (not recommended for production)
    app.run(host="0.0.0.0", port=3001, debug=False)


# ---------------------- Security: Basic Auth ----------------------
# Protect the entire app with Basic Auth using MGMT_USER/MGMT_PASS env vars
from functools import wraps


def _get_mgmt_creds():
    user = os.environ.get("MGMT_USER", "shair")
    pwd = os.environ.get("MGMT_PASS", "")
    return user, pwd


def _auth_required_response():
    return Response(
        "Authentication required",
        401,
        {"WWW-Authenticate": 'Basic realm="Pipe Management"'},
    )


@app.before_request
def _enforce_basic_auth():
    user, pwd = _get_mgmt_creds()
    # Require a non-empty password
    if not user or not pwd:
        return None
    auth = request.authorization
    if not auth or auth.username != user or auth.password != pwd:
        return _auth_required_response()
    return None









