"""Checks Resources/mlx_audio_worker.py against fake mlx_audio, mlx, and
huggingface_hub packages: serving, option filtering, cancellation, model
switching, parent-death exit, and download progress. Needs numpy; downloads and
loads nothing real.

  python3 Tests/mlx_audio_worker_checks.py
"""

import io
import json
import os
import signal
import subprocess
import sys
import tempfile
import textwrap
import threading
import time
import urllib.error
import urllib.request
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKER = os.path.join(ROOT, "Resources", "mlx_audio_worker.py")

FAKES = {
    "mlx/__init__.py": "",
    "mlx/core.py": "def clear_cache():\n    pass\n",
    "mlx_audio/__init__.py": "__version__ = '0.0-fake'\n",
    "mlx_audio/tts/__init__.py": "",
    "mlx_audio/tts/utils.py": """
        import json, os, time

        class Result:
            def __init__(self, audio, sample_rate):
                self.audio = audio
                self.sample_rate = sample_rate

        class Model:
            sample_rate = 16000

            def __init__(self, repo):
                self.repo = repo

            def record(self, method, text, options):
                with open(os.environ["FAKE_CALLS"], "a") as calls:
                    calls.write(json.dumps({"repo": self.repo, "method": method, "text": text, "options": options}) + "\\n")

            def generate(self, text, voice=None, temperature=0.7, verbose=False):
                self.record("generate", text, {"voice": voice, "temperature": temperature})
                segments = 20 if text == "slow" else 2
                for _ in range(segments):
                    if text == "slow":
                        time.sleep(0.1)
                    yield Result([0.5] * 80, 16000)

            def generate_voice_design(self, text, instruct=None, **kwargs):
                self.record("generate_voice_design", text, dict(kwargs, instruct=instruct))
                yield Result([0.25] * 40, 24000)

        def load_model(repo):
            if repo == "bad/model":
                raise ValueError("no such model")
            with open(os.environ["FAKE_LOADS"], "a") as loads:
                loads.write(repo + "\\n")
            return Model(repo)
    """,
    "huggingface_hub/__init__.py": """
        import os, time
        from huggingface_hub import constants

        class Sibling:
            def __init__(self, size):
                self.size = size

        class Info:
            siblings = [Sibling(3000), Sibling(1000)]

        class HfApi:
            def model_info(self, repo, files_metadata=False):
                return Info()

        def snapshot_download(repo_id):
            if repo_id == "missing/repo":
                raise OSError("Repository not found")
            folder = os.path.join(constants.HF_HUB_CACHE, "models--" + repo_id.replace("/", "--"))
            blobs = os.path.join(folder, "blobs")
            snapshot = os.path.join(folder, "snapshots", "main")
            os.makedirs(blobs, exist_ok=True)
            os.makedirs(snapshot, exist_ok=True)
            for index in range(4):
                with open(os.path.join(blobs, "part%d" % index), "wb") as part:
                    part.write(b"x" * 1000)
                time.sleep(0.3)
            open(os.path.join(snapshot, "config.json"), "w").close()
            return snapshot
    """,
    "huggingface_hub/constants.py": "import os\nHF_HUB_CACHE = os.environ['FAKE_HUB']\n",
}


def write_fakes(directory):
    for path, source in FAKES.items():
        full = os.path.join(directory, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w") as handle:
            handle.write(textwrap.dedent(source))


def environment(fakes, scratch):
    env = dict(os.environ)
    env["PYTHONPATH"] = fakes
    env["FAKE_CALLS"] = os.path.join(scratch, "calls.jsonl")
    env["FAKE_LOADS"] = os.path.join(scratch, "loads.txt")
    env["FAKE_HUB"] = os.path.join(scratch, "hub")
    return env


def events(output):
    return [json.loads(line) for line in output.splitlines() if line.startswith("{")]


def post(port, path, body, timeout=10):
    request = urllib.request.Request(
        "http://127.0.0.1:%d%s" % (port, path),
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, dict(response.headers), response.read()
    except urllib.error.HTTPError as error:
        return error.code, dict(error.headers), error.read()


def start_worker(env, parent_pid):
    process = subprocess.Popen(
        [sys.executable, "-u", WORKER, "serve", "--port", "0", "--parent-pid", str(parent_pid)],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, env=env, text=True,
    )
    line = json.loads(process.stdout.readline())
    assert line["event"] == "listening" and line["port"] > 0, line
    return process, line["port"]


def check_command(env):
    result = subprocess.run([sys.executable, WORKER, "check"], env=env, capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, result.stderr
    (event,) = events(result.stdout)
    assert event == {"event": "ok", "mlx_audio": "0.0-fake", "hub_cache": env["FAKE_HUB"]}, event


def check_serving(env):
    process, port = start_worker(env, os.getpid())
    try:
        with urllib.request.urlopen("http://127.0.0.1:%d/health" % port, timeout=5) as response:
            assert json.loads(response.read()) == {"status": "ok", "model": None}

        status, _, _ = post(port, "/v1/models", {"model": "fake/a"})
        assert status == 200

        status, headers, body = post(port, "/v1/audio/speech", {
            "model": "fake/a", "input": "Hello there.", "voice": "tara", "temperature": 0.6,
            "exaggeration": 0.9, "cfg_weight": 0.3, "request_id": "r1",
        })
        assert status == 200 and headers["Content-Type"] == "audio/wav", (status, body)
        with wave.open(io.BytesIO(body)) as audio:
            assert audio.getframerate() == 16000 and audio.getnchannels() == 1 and audio.getsampwidth() == 2
            assert audio.getnframes() == 160, "segments are concatenated"
        assert headers["X-Sample-Rate"] == "16000"

        calls = [json.loads(line) for line in open(env["FAKE_CALLS"])]
        assert calls[-1]["options"] == {"voice": "tara", "temperature": 0.6}, "options generate() lacks are dropped"

        status, _, body = post(port, "/v1/audio/speech", {
            "model": "fake/a", "input": "Narrate.", "mode": "voice_design", "instruct": "A calm narrator",
            "exaggeration": 0.9,
        })
        assert status == 200
        calls = [json.loads(line) for line in open(env["FAKE_CALLS"])]
        assert calls[-1]["method"] == "generate_voice_design"
        assert calls[-1]["options"]["instruct"] == "A calm narrator"
        assert calls[-1]["options"]["exaggeration"] == 0.9, "**kwargs methods get every option"

        # Switching models replaces the loaded one; reloading the same is free.
        post(port, "/v1/models", {"model": "fake/b"})
        post(port, "/v1/models", {"model": "fake/b"})
        assert open(env["FAKE_LOADS"]).read().split() == ["fake/a", "fake/b"]

        status, _, body = post(port, "/v1/models", {"model": "bad/model"})
        assert status == 500 and b"no such model" in body
        status, _, _ = post(port, "/v1/audio/speech", {"input": "no model"})
        assert status == 400

        # Cancelling stops a long request between segments.
        result = {}

        def slow():
            result["response"] = post(port, "/v1/audio/speech", {"model": "fake/a", "input": "slow", "request_id": "r2"})

        thread = threading.Thread(target=slow)
        started = time.time()
        thread.start()
        time.sleep(0.4)
        post(port, "/v1/cancel", {"request_id": "other"})
        post(port, "/v1/cancel", {"request_id": "r2"})
        thread.join(5)
        assert result["response"][0] == 499, result
        assert time.time() - started < 1.5, "cancellation is prompt"

        # A cancel that arrives before its request still applies.
        post(port, "/v1/cancel", {"request_id": "r3"})
        status, _, _ = post(port, "/v1/audio/speech", {"model": "fake/a", "input": "Hi.", "request_id": "r3"})
        assert status == 499
        status, _, _ = post(port, "/v1/audio/speech", {"model": "fake/a", "input": "Hi.", "request_id": "r4"})
        assert status == 200
    finally:
        process.terminate()
        process.wait(5)


def check_parent_exit(env):
    # An intermediate process starts the worker as its child, then dies.
    launcher = textwrap.dedent("""
        import os, subprocess, sys, time
        worker = subprocess.Popen([sys.executable, "-u", sys.argv[1], "serve", "--port", "0",
                                   "--parent-pid", str(os.getpid())], stdout=subprocess.DEVNULL)
        print(worker.pid, flush=True)
        time.sleep(60)
    """)
    parent = subprocess.Popen([sys.executable, "-c", launcher, WORKER], stdout=subprocess.PIPE, env=env, text=True)
    worker_pid = int(parent.stdout.readline())
    time.sleep(0.5)
    os.kill(parent.pid, signal.SIGKILL)
    parent.wait()
    deadline = time.time() + 5
    while time.time() < deadline:
        try:
            os.kill(worker_pid, 0)
        except OSError:
            return
        time.sleep(0.1)
    os.kill(worker_pid, signal.SIGKILL)
    raise AssertionError("the worker outlived its parent")


def check_download(env):
    result = subprocess.run([sys.executable, "-u", WORKER, "download", "fake/model"],
                            env=env, capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, result.stderr
    stream = events(result.stdout)
    assert stream[0] == {"event": "total", "bytes": 4000}, stream[0]
    progress = [event["bytes"] for event in stream if event["event"] == "progress"]
    assert len(progress) >= 2 and progress == sorted(progress) and progress[-1] == 4000, progress
    assert {"event": "phase", "phase": "verifying"} in stream
    assert stream[-1]["event"] == "done"
    assert "fake/model" in open(env["FAKE_LOADS"]).read().split(), "the model is loaded once to fetch dependencies"

    failed = subprocess.run([sys.executable, "-u", WORKER, "download", "missing/repo"],
                            env=env, capture_output=True, text=True, timeout=30)
    assert failed.returncode == 1
    assert events(failed.stdout)[-1] == {"event": "error", "message": "OSError: Repository not found"}


def main():
    with tempfile.TemporaryDirectory() as scratch:
        fakes = os.path.join(scratch, "fakes")
        write_fakes(fakes)
        env = environment(fakes, scratch)
        os.makedirs(env["FAKE_HUB"])
        check_command(env)
        check_serving(env)
        check_parent_exit(env)
        check_download(env)
    print("mlx-audio worker checks passed")


if __name__ == "__main__":
    main()
