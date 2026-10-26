"""Operate the real native game through X11 input and unedited screen captures.

This is a desktop mouse playtest, not a physical Android, touch, or human test.
No game commands, solutions, saved-state edits, or internal scene APIs are used.
"""
from pathlib import Path
import argparse
import ctypes as C
import datetime as dt
import hashlib
import json
import os
import select
import signal
import socket
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SESSION = ROOT / "build/player-session"
DEFAULT_EVIDENCE = ROOT / "docs/playtests/2026-10-26-player/session"
GODOT = Path("/workspace/setup-tools/Godot_v4.7.2-stable_linux.x86_64")
XVFB = Path("/workspace/setup-tools/native/bin/Xvfb")


def utc():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def alive(pid):
    if not pid:
        return False
    try:
        os.kill(pid, 0)
        return Path(f"/proc/{pid}/stat").read_text().rpartition(")")[2].split()[0] != "Z"
    except (ProcessLookupError, FileNotFoundError):
        return False


def process_identity(pid):
    """Record Linux process identity without retaining its command-line text."""
    process = Path(f"/proc/{pid}")
    fields = (process / "stat").read_text().rpartition(")")[2].split()
    return {"pid": pid, "start_time_ticks": fields[19],
            "boot_id": Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
            "cmdline_sha256": hashlib.sha256((process / "cmdline").read_bytes()).hexdigest()}


def require_identity(pid, expected):
    if not alive(pid):
        return False
    if not expected or expected.get("pid") != pid:
        raise RuntimeError("Refusing process control: no recorded identity for the live PID")
    process = Path(f"/proc/{pid}")
    try:
        start_time = (process / "stat").read_text().rpartition(")")[2].split()[19]
        boot = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
        if start_time != expected.get("start_time_ticks") or boot != expected.get("boot_id"):
            raise RuntimeError("Refusing process control: PID identity changed")
        if process_identity(pid) != expected:
            raise RuntimeError("Refusing process control: command line changed")
    except (FileNotFoundError, ProcessLookupError):
        return False
    return True


def terminate(pid, expected):
    """Validate identity, then signal the pinned process rather than a reusable PID."""
    if not alive(pid):
        return
    try:
        descriptor = os.pidfd_open(pid)
    except ProcessLookupError:
        return
    try:
        if not require_identity(pid, expected):
            return
        try:
            signal.pidfd_send_signal(descriptor, signal.SIGTERM)
            if not select.select([descriptor], [], [], 5)[0]:
                signal.pidfd_send_signal(descriptor, signal.SIGKILL)
                if not select.select([descriptor], [], [], 5)[0]:
                    raise RuntimeError("The recorded process did not exit within the bounded stop wait")
        except ProcessLookupError:
            pass
    finally:
        os.close(descriptor)


class Input:
    def __init__(self, display):
        self.x = C.CDLL("libX11.so.6")
        self.t = C.CDLL("libXtst.so.6")
        self.x.XOpenDisplay.argtypes = [C.c_char_p]
        self.x.XOpenDisplay.restype = C.c_void_p
        self.d = self.x.XOpenDisplay(display.encode())
        if not self.d:
            raise RuntimeError("Cannot connect to the session X display")
        self.x.XFlush.argtypes = [C.c_void_p]
        self.x.XCloseDisplay.argtypes = [C.c_void_p]
        self.x.XDefaultRootWindow.argtypes = [C.c_void_p]
        self.x.XDefaultRootWindow.restype = C.c_ulong
        self.x.XQueryTree.argtypes = [C.c_void_p, C.c_ulong, C.POINTER(C.c_ulong), C.POINTER(C.c_ulong), C.POINTER(C.POINTER(C.c_ulong)), C.POINTER(C.c_uint)]
        self.x.XFree.argtypes = [C.c_void_p]
        self.x.XSetInputFocus.argtypes = [C.c_void_p, C.c_ulong, C.c_int, C.c_ulong]
        self.x.XStringToKeysym.argtypes = [C.c_char_p]
        self.x.XStringToKeysym.restype = C.c_ulong
        self.x.XKeysymToKeycode.argtypes = [C.c_void_p, C.c_ulong]
        self.x.XKeysymToKeycode.restype = C.c_uint
        self.t.XTestFakeMotionEvent.argtypes = [C.c_void_p, C.c_int, C.c_int, C.c_int, C.c_ulong]
        self.t.XTestFakeButtonEvent.argtypes = [C.c_void_p, C.c_uint, C.c_int, C.c_ulong]
        self.t.XTestFakeKeyEvent.argtypes = [C.c_void_p, C.c_uint, C.c_int, C.c_ulong]
        root = self.x.XDefaultRootWindow(self.d)
        root_return, parent, children, count = C.c_ulong(), C.c_ulong(), C.POINTER(C.c_ulong)(), C.c_uint()
        self.x.XQueryTree(self.d, root, C.byref(root_return), C.byref(parent), C.byref(children), C.byref(count))
        if count.value:
            self.x.XSetInputFocus(self.d, children[count.value - 1], 2, 0)
        if children:
            self.x.XFree(children)
        self.flush()

    def flush(self):
        self.x.XFlush(self.d)

    def move(self, x, y):
        self.t.XTestFakeMotionEvent(self.d, 0, x, y, 0)
        self.flush()

    def button(self, n, down):
        self.t.XTestFakeButtonEvent(self.d, n, int(down), 0)
        self.flush()

    def click(self, x, y, n=1):
        self.move(x, y)
        time.sleep(.05)
        self.button(n, True)
        time.sleep(.06)
        self.button(n, False)

    def key(self, name):
        aliases = {"ctrl": "Control_L", "alt": "Alt_L", "shift": "Shift_L", "enter": "Return", "escape": "Escape", "space": "space"}
        names = [aliases.get(n.lower(), n) for n in name.split("+")]
        codes = [self.x.XKeysymToKeycode(self.d, self.x.XStringToKeysym(n.encode())) for n in names]
        if not all(codes):
            raise ValueError("Unknown X11 key: " + name)
        for code in codes:
            self.t.XTestFakeKeyEvent(self.d, code, 1, 0)
        self.flush()
        time.sleep(.08)
        for code in reversed(codes):
            self.t.XTestFakeKeyEvent(self.d, code, 0, 0)
        self.flush()

    def close(self):
        self.x.XCloseDisplay(self.d)


def launch_game(state):
    profile = Path(state["profile"])
    env = os.environ.copy()
    env.update(DISPLAY=state["display"], LIBGL_ALWAYS_SOFTWARE="1",
               XDG_DATA_HOME=str(profile / "data"), XDG_CONFIG_HOME=str(profile / "config"),
               XDG_CACHE_HOME=str(profile / "cache"), MESA_SHADER_CACHE_DIR=str(profile / "shader-cache"))
    for part in ("data", "config", "cache", "shader-cache"):
        (profile / part).mkdir(parents=True, exist_ok=True)
    command = [str(GODOT), "--windowed", "--path", str(ROOT), "--audio-driver", "Dummy",
               "--resolution", state["resolution"], "--position", "0,0"]
    with Path(state["game_log"]).open("ab") as log:
        process = subprocess.Popen(command, env=env, stdout=log, stderr=log, start_new_session=True, cwd=ROOT)
    state["game_pid"] = process.pid
    state["game_identity"] = process_identity(process.pid)
    state["launch_command"] = command
    from PIL import Image, ImageStat
    started = time.monotonic()
    probe = profile / "boot-screen.png"
    for _ in range(25):
        if not alive(process.pid):
            raise RuntimeError("Game exited during boot; see " + state["game_log"])
        time.sleep(1)
        subprocess.run(["/usr/bin/import", "-display", state["display"], "-window", "root", str(probe)], check=True, timeout=10, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        with Image.open(probe) as picture:
            visible = sum(ImageStat.Stat(picture.convert("RGB")).var) > 30
        if visible:
            state["boot_visible_after_seconds"] = round(time.monotonic() - started, 3)
            time.sleep(.5)
            return
    raise RuntimeError("No nonblank native frame appeared within the bounded startup wait")


def capture(state, action, note, details=None):
    out = Path(state["evidence_dir"])
    out.mkdir(parents=True, exist_ok=True)
    journal = out / "events.jsonl"
    previous = [json.loads(line) for line in journal.read_text().splitlines()] if journal.exists() else []
    index = len(previous)
    path = out / f"{index:04d}-{action}.png"
    subprocess.run(["/usr/bin/import", "-display", state["display"], "-window", "root", str(path)], check=True, timeout=20, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    from PIL import Image
    with Image.open(path) as picture:
        dimensions = list(picture.size)
    expected = list(map(int, state["resolution"].split("x")))
    if dimensions != expected:
        raise RuntimeError(f"Capture dimensions {dimensions} differ from {expected}")
    row = {"index": index, "time_utc": utc(), "action": action, "note": note,
           "details": details or {}, "screenshot": str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path),
           "dimensions": dimensions, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
           "before_screenshot": previous[-1]["screenshot"] if previous else None,
           "method": "native X11 screen capture; XTest desktop mouse/keyboard input", "game_pid": state["game_pid"]}
    with journal.open("a") as output:
        output.write(json.dumps(row, ensure_ascii=False) + "\n")
    print(json.dumps(row, ensure_ascii=False))
    return row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--session-dir", type=Path, default=DEFAULT_SESSION)
    parser.add_argument("--note", default="", help="Player intent or observation, stored verbatim in the input journal")
    parser.add_argument("--wait", type=float, default=.7, help="Post-input rendering wait, 0–10 seconds")
    sub = parser.add_subparsers(dest="action", required=True)
    start = sub.add_parser("start")
    start.add_argument("--display", type=int, default=103)
    start.add_argument("--resolution", default="844x390")
    start.add_argument("--evidence-dir", type=Path, default=DEFAULT_EVIDENCE)
    click = sub.add_parser("click"); click.add_argument("x", type=int); click.add_argument("y", type=int)
    key = sub.add_parser("key"); key.add_argument("name")
    drag = sub.add_parser("drag")
    for arg in ("x1", "y1", "x2", "y2"):
        drag.add_argument(arg, type=int)
    scroll = sub.add_parser("scroll"); scroll.add_argument("direction", choices=["up", "down"]); scroll.add_argument("steps", type=int, nargs="?", default=3)
    scroll.add_argument("--x", type=int, default=740); scroll.add_argument("--y", type=int, default=250)
    for action in ("capture", "restart", "stop", "status"):
        sub.add_parser(action)
    args = parser.parse_args()
    if not 0 <= args.wait <= 10:
        parser.error("--wait must be between 0 and 10 seconds")
    directory = args.session_dir.resolve(); directory.mkdir(parents=True, exist_ok=True)
    state_file = directory / "session.json"
    state = json.loads(state_file.read_text()) if state_file.exists() else {}
    if args.action == "start":
        if alive(state.get("game_pid")) or alive(state.get("xvfb_pid")):
            raise SystemExit("A session is already running; use stop before start or restart to retain this profile")
        evidence = args.evidence_dir.resolve()
        if evidence.exists() and (not evidence.is_dir() or any(evidence.iterdir())):
            raise SystemExit("Evidence directory is not empty; choose a fresh --evidence-dir. Existing evidence was preserved")
        width, height = map(int, args.resolution.split("x"))
        if width < 640 or height < 300 or width > 2400 or height > 1400:
            parser.error("Unsupported playtest resolution")
        from verify_project import runtime_manifest
        manifest = runtime_manifest()
        profile = directory / ("profile-" + dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d-%H%M%S-%f"))
        tool_cache = directory / "tool-cache"
        tool_cache.mkdir(exist_ok=True)
        state = {"created_at": utc(), "display": "127.0.0.1:" + str(args.display), "display_number": args.display,
                 "resolution": args.resolution, "profile": str(profile), "game_log": str(directory / "godot.log"),
                 "evidence_dir": str(args.evidence_dir.resolve()), "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                 "runtime_digest_sha256": hashlib.sha256(json.dumps(manifest, sort_keys=True, separators=(",", ":")).encode()).hexdigest(),
                 "godot_version": subprocess.check_output([str(GODOT), "--headless", "--version"], env={**os.environ, "XDG_CACHE_HOME": str(tool_cache)}, text=True).strip(),
                 "method": "native Godot on Xvfb/Mesa; XTest mouse/keyboard; unedited ImageMagick screen capture",
                 "audio_driver": "Dummy", "physical_android": False, "synthetic_touch": False, "human_player": False}
        command = [str(XVFB), ":" + str(args.display), "-screen", "0", args.resolution + "x24", "-ac", "-nolisten", "unix", "-nolisten", "local", "-listen", "tcp"]
        with (directory / "xvfb.log").open("ab") as log:
            server = subprocess.Popen(command, stdout=log, stderr=log, start_new_session=True)
        state["xvfb_pid"] = server.pid
        try:
            for _ in range(50):
                if not alive(server.pid):
                    raise RuntimeError("Xvfb startup failed; see xvfb.log")
                try:
                    with socket.create_connection(("127.0.0.1", 6000 + args.display), timeout=.1):
                        break
                except OSError:
                    time.sleep(.1)
            else:
                raise RuntimeError("Xvfb did not start")
            state["xvfb_identity"] = process_identity(server.pid)
            launch_game(state)
        except Exception:
            terminate(state.get("game_pid"), state.get("game_identity"))
            # This direct, unreaped Popen child cannot have its PID reused.
            if server.poll() is None:
                server.terminate()
                try:
                    server.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    server.kill(); server.wait(timeout=5)
            raise
        state_file.write_text(json.dumps(state, indent=2) + "\n")
        Path(state["evidence_dir"]).mkdir(parents=True, exist_ok=True)
        (Path(state["evidence_dir"]) / "session-manifest.json").write_text(json.dumps(state, indent=2) + "\n")
        capture(state, "start", args.note)
        return
    if not state:
        raise SystemExit("No session exists; run start first")
    if args.action == "status":
        print(json.dumps({**state, "game_alive": alive(state.get("game_pid")), "xvfb_alive": alive(state.get("xvfb_pid"))}, indent=2)); return
    if args.action == "stop":
        require_identity(state.get("game_pid"), state.get("game_identity"))
        require_identity(state.get("xvfb_pid"), state.get("xvfb_identity"))
        terminate(state.get("game_pid"), state.get("game_identity"))
        terminate(state.get("xvfb_pid"), state.get("xvfb_identity"))
        state["stopped_at"] = utc(); state_file.write_text(json.dumps(state, indent=2) + "\n")
        print("Stopped only the recorded game and Xvfb; save profile retained"); return
    if args.action == "restart":
        require_identity(state.get("game_pid"), state.get("game_identity"))
        if not require_identity(state.get("xvfb_pid"), state.get("xvfb_identity")):
            raise SystemExit("Xvfb is not running; use start with a fresh evidence directory")
        terminate(state.get("game_pid"), state.get("game_identity")); launch_game(state)
        state_file.write_text(json.dumps(state, indent=2) + "\n")
        capture(state, "restart", args.note); return
    if not alive(state.get("game_pid")):
        raise SystemExit("Game is not running")
    require_identity(state.get("game_pid"), state.get("game_identity"))
    require_identity(state.get("xvfb_pid"), state.get("xvfb_identity"))
    details = {}
    if args.action != "capture":
        device = Input(state["display"])
        try:
            if args.action == "click":
                width, height = map(int, state["resolution"].split("x"))
                if not (0 <= args.x < width and 0 <= args.y < height):
                    raise ValueError("Coordinates outside the displayed viewport")
                device.click(args.x, args.y); details = {"x": args.x, "y": args.y, "button": 1}
            elif args.action == "key":
                device.key(args.name); details = {"key": args.name}
            elif args.action == "scroll":
                if not 1 <= args.steps <= 30:
                    raise ValueError("Scroll steps must be 1–30")
                for _ in range(args.steps):
                    device.click(args.x, args.y, 4 if args.direction == "up" else 5)
                details = {"direction": args.direction, "steps": args.steps, "x": args.x, "y": args.y}
            elif args.action == "drag":
                device.move(args.x1, args.y1); device.button(1, True)
                for step in range(1, 21):
                    device.move(round(args.x1 + (args.x2-args.x1)*step/20), round(args.y1 + (args.y2-args.y1)*step/20)); time.sleep(.025)
                device.button(1, False); details = {"from": [args.x1,args.y1], "to": [args.x2,args.y2]}
        finally:
            device.close()
    time.sleep(args.wait)
    capture(state, args.action, args.note, details)


if __name__ == "__main__":
    main()
