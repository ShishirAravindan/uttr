"""uttr's bridge to mlx-audio speech models on the Apple Silicon GPU.

uttr starts this script with the Python of its managed mlx-audio environment:

  serve --port 0 --parent-pid PID
      Serves HTTP on 127.0.0.1 and prints {"event": "listening", "port": N}.
      Exits when its parent goes away, so a crashed uttr never leaves a model
      holding unified memory.
  download REPO
      Downloads a model from Hugging Face, printing JSON progress lines, then
      loads it once so codecs and other dependent files are fetched too.
  check
      Confirms mlx-audio imports and prints the Hugging Face cache path.

Endpoints (JSON in, JSON or WAV out):
  GET  /health            {"status": "ok", "model": REPO or null}
  POST /v1/models         {"model": REPO}; loads it, replacing the loaded one
  POST /v1/audio/speech   {"model", "input", "voice", "instruct", "mode",
                           "lang_code", "temperature", "exaggeration",
                           "cfg_weight", "request_id"}; returns 16-bit mono WAV
  POST /v1/cancel         {"request_id"}; stops that request between segments

Only the standard library and mlx-audio's own dependencies are used. Options a
model's generate() doesn't accept are dropped, so one request shape serves every
model family.
"""

import argparse
import gc
import inspect
import io
import json
import os
import sys
import threading
import time
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

GENERATION_OPTIONS = ("voice", "instruct", "lang_code", "temperature", "exaggeration", "cfg_weight")


def emit(event, **fields):
    fields["event"] = event
    sys.stdout.write(json.dumps(fields) + "\n")
    sys.stdout.flush()


def load_model(repo):
    try:
        from mlx_audio.tts.utils import load_model as load
    except ImportError:
        from mlx_audio.tts.generate import load_model as load
    return load(repo)


def clear_gpu_cache():
    try:
        import mlx.core as mx

        clear = getattr(mx, "clear_cache", None) or getattr(getattr(mx, "metal", None), "clear_cache", None)
        if clear:
            clear()
    except Exception:
        pass


class Cancelled(Exception):
    pass


def accepted_options(method, options):
    """The options `method` accepts; everything if it takes **kwargs."""
    try:
        parameters = inspect.signature(method).parameters.values()
    except (TypeError, ValueError):
        return options
    if any(p.kind == inspect.Parameter.VAR_KEYWORD for p in parameters):
        return options
    names = {p.name for p in parameters}
    return {key: value for key, value in options.items() if key in names}


def generation_method(model, mode):
    if mode == "voice_design" and hasattr(model, "generate_voice_design"):
        return model.generate_voice_design
    if mode == "custom_voice" and hasattr(model, "generate_custom_voice"):
        return model.generate_custom_voice
    return model.generate


def synthesize(model, request, is_cancelled):
    """Runs one request and returns (float samples, sample rate)."""
    import numpy as np

    method = generation_method(model, request.get("mode"))
    options = {key: request[key] for key in GENERATION_OPTIONS if request.get(key) is not None}
    options["verbose"] = False
    options = accepted_options(method, options)
    output = method(request["input"], **options)
    if not hasattr(output, "__iter__") or hasattr(output, "shape"):
        output = [output]

    pieces = []
    sample_rate = None
    for result in output:
        if is_cancelled():
            raise Cancelled()
        audio = getattr(result, "audio", result)
        sample_rate = getattr(result, "sample_rate", None) or sample_rate
        pieces.append(np.asarray(audio, dtype=np.float32).reshape(-1))
    if is_cancelled():
        raise Cancelled()
    sample_rate = int(sample_rate or getattr(model, "sample_rate", 24000))
    samples = np.concatenate(pieces) if pieces else np.zeros(0, dtype=np.float32)
    return samples, sample_rate


def wav_bytes(samples, sample_rate):
    import numpy as np

    pcm = (np.clip(samples, -1.0, 1.0) * 32767.0).astype("<i2")
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(sample_rate)
        out.writeframes(pcm.tobytes())
    return buffer.getvalue()


class Worker:
    """One loaded model at a time; requests run one after another."""

    def __init__(self, loader=load_model):
        self.loader = loader
        self.repo = None
        self.model = None
        self.lock = threading.Lock()
        self.state_lock = threading.Lock()
        self.current_request = None
        self.cancelled = set()

    def ensure_model(self, repo):
        if self.repo == repo:
            return self.model
        # Free the previous model before loading the next, so two never share memory.
        self.model = None
        self.repo = None
        gc.collect()
        clear_gpu_cache()
        self.model = self.loader(repo)
        self.repo = repo
        return self.model

    def load(self, repo):
        with self.lock:
            self.ensure_model(repo)

    def speak(self, request):
        request_id = request.get("request_id")
        with self.lock:
            with self.state_lock:
                if request_id in self.cancelled:
                    self.cancelled.discard(request_id)
                    raise Cancelled()
                self.current_request = request_id
            try:
                model = self.ensure_model(request["model"])
                return synthesize(model, request, lambda: self.is_cancelled(request_id))
            finally:
                with self.state_lock:
                    self.current_request = None
                    self.cancelled.discard(request_id)

    def is_cancelled(self, request_id):
        with self.state_lock:
            return request_id is not None and request_id in self.cancelled

    def cancel(self, request_id):
        if request_id is None:
            return
        with self.state_lock:
            self.cancelled.add(request_id)
            # Forget cancellations for requests that never arrive.
            if len(self.cancelled) > 64:
                self.cancelled = {request_id}


def make_handler(worker):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, format, *args):
            sys.stderr.write("[worker] " + (format % args) + "\n")

        def send_json(self, status, body):
            payload = json.dumps(body).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def read_json(self):
            length = int(self.headers.get("Content-Length") or 0)
            return json.loads(self.rfile.read(length) or b"{}")

        def do_GET(self):
            if self.path == "/health":
                self.send_json(200, {"status": "ok", "model": worker.repo})
            else:
                self.send_json(404, {"error": "not found"})

        def do_POST(self):
            try:
                body = self.read_json()
            except ValueError:
                self.send_json(400, {"error": "invalid JSON"})
                return
            try:
                if self.path == "/v1/models":
                    worker.load(body["model"])
                    self.send_json(200, {"status": "ok", "model": worker.repo})
                elif self.path == "/v1/audio/speech":
                    started = time.time()
                    samples, rate = worker.speak(body)
                    audio = wav_bytes(samples, rate)
                    sys.stderr.write("[worker] %.2fs of audio in %.2fs\n" % (len(samples) / rate, time.time() - started))
                    self.send_response(200)
                    self.send_header("Content-Type", "audio/wav")
                    self.send_header("Content-Length", str(len(audio)))
                    self.send_header("X-Sample-Rate", str(rate))
                    self.end_headers()
                    self.wfile.write(audio)
                elif self.path == "/v1/cancel":
                    worker.cancel(body.get("request_id"))
                    self.send_json(200, {"status": "ok"})
                else:
                    self.send_json(404, {"error": "not found"})
            except Cancelled:
                self.send_json(499, {"error": "cancelled"})
            except KeyError as error:
                self.send_json(400, {"error": "missing field %s" % error})
            except Exception as error:  # Report model errors to uttr instead of dropping the connection.
                sys.stderr.write("[worker] error: %r\n" % (error,))
                self.send_json(500, {"error": "%s: %s" % (type(error).__name__, error)})

    return Handler


def watch_parent(parent_pid):
    while True:
        if os.getppid() != parent_pid:
            os._exit(0)
        try:
            os.kill(parent_pid, 0)
        except OSError:
            os._exit(0)
        time.sleep(1)


def serve(port, parent_pid, worker=None):
    worker = worker or Worker()
    server = ThreadingHTTPServer(("127.0.0.1", port), make_handler(worker))
    server.daemon_threads = True
    if parent_pid:
        threading.Thread(target=watch_parent, args=(parent_pid,), daemon=True).start()
    emit("listening", port=server.server_address[1])
    server.serve_forever()


def hub_cache():
    from huggingface_hub import constants

    return constants.HF_HUB_CACHE


def directory_size(path):
    total = 0
    for root, _, files in os.walk(path):
        for name in files:
            try:
                total += os.lstat(os.path.join(root, name)).st_size
            except OSError:
                pass
    return total


def download(repo, verify=True):
    from huggingface_hub import HfApi, snapshot_download

    total = 0
    try:
        info = HfApi().model_info(repo, files_metadata=True)
        total = sum((sibling.size or 0) for sibling in (info.siblings or []))
    except Exception as error:
        sys.stderr.write("[worker] size lookup failed: %r\n" % (error,))
    emit("total", bytes=total)

    folder = os.path.join(hub_cache(), "models--" + repo.replace("/", "--"))
    finished = threading.Event()

    def report():
        while not finished.wait(0.5):
            emit("progress", bytes=directory_size(folder), total=total)

    reporter = threading.Thread(target=report, daemon=True)
    reporter.start()
    try:
        path = snapshot_download(repo_id=repo)
    finally:
        finished.set()
        reporter.join()
    emit("progress", bytes=directory_size(folder), total=total)
    if verify:
        emit("phase", phase="verifying")
        load_model(repo)
    emit("done", path=path)


def check():
    import mlx_audio  # noqa: F401
    import mlx.core  # noqa: F401

    version = getattr(mlx_audio, "__version__", None)
    if version is None:
        try:
            from importlib.metadata import version as package_version

            version = package_version("mlx-audio")
        except Exception:
            version = "unknown"
    emit("ok", mlx_audio=version, hub_cache=hub_cache())


def main(argv=None):
    parser = argparse.ArgumentParser(prog="mlx_audio_worker")
    commands = parser.add_subparsers(dest="command", required=True)
    serve_parser = commands.add_parser("serve")
    serve_parser.add_argument("--port", type=int, default=0)
    serve_parser.add_argument("--parent-pid", type=int, default=0)
    download_parser = commands.add_parser("download")
    download_parser.add_argument("repo")
    download_parser.add_argument("--no-verify", action="store_true")
    commands.add_parser("check")
    args = parser.parse_args(argv)

    try:
        if args.command == "serve":
            serve(args.port, args.parent_pid)
        elif args.command == "download":
            download(args.repo, verify=not args.no_verify)
        else:
            check()
    except KeyboardInterrupt:
        return 0
    except Exception as error:
        emit("error", message="%s: %s" % (type(error).__name__, error))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
