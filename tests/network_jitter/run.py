#!/usr/bin/env python3
import argparse
import contextlib
import heapq
import itertools
import json
import random
import select
import shutil
import socket
import statistics
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
NETFOX_TAG = "v1.35.3"
NETFOX_REV = "c7fc6ea52b4e9087c980d9ca1f8c3826e3a6caa4"
SPEED = 3.8
ROLES = ("host", "shooter", "observer")
TRACKS = ("current", "netfox", "netfox_buffer")
PROFILES = {"loopback": (0, 0, 0), "rtt80": (80, 10, 0.01), "rtt150": (150, 10, 0.01)}


class Link:
    def __init__(self, server, profile, seed):
        self.server = server
        self.client = None
        self.rtt, self.jitter, self.loss = profile
        self.rng = [random.Random(seed), random.Random(seed + 1)]
        self.total = [0, 0]
        self.dropped = [0, 0]
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.socket.bind(("127.0.0.1", 0))
        self.socket.setblocking(False)

    def receive(self, queue, order, blackout_until):
        while True:
            try:
                packet, sender = self.socket.recvfrom(65535)
            except BlockingIOError:
                return
            direction = int(sender == self.server)
            if direction == 0:
                self.client = sender
            destination = self.client if direction else self.server
            if destination is None:
                continue
            self.total[direction] += 1
            rng = self.rng[direction]
            if rng.random() < self.loss or (direction == 0 and time.monotonic() < blackout_until):
                self.dropped[direction] += 1
                continue
            delay = (self.rtt / 2 + rng.uniform(-self.jitter, self.jitter)) / 1000
            heapq.heappush(queue, (time.monotonic() + delay, next(order), self.socket, destination, packet))


def stage(work, netfox, godot, log, source_root=ROOT, native=False):
    project = work / "project"
    project.mkdir()
    for name in ("addons", "assets", "game"):
        shutil.copytree(source_root / name, project / name)
    shutil.copytree(ROOT / "tests/network_jitter", project / "tests/network_jitter")
    imports = source_root / ".godot/imported"
    if imports.is_dir():
        shutil.copytree(imports, project / ".godot/imported")
    for name in ("project.godot", "default_bus_layout.tres"):
        shutil.copy2(source_root / name, project / name)
    config = project / "project.godot"
    config_text = config.read_text().replace('config/name="shoot-container"', 'config/name="shooter-network-jitter"', 1)
    config.write_text(config_text)
    if not native:
        add_netfox(work, netfox, project)
    with log.open("w") as output:
        subprocess.run([godot, "--headless", "--path", project, "--import"],
                       stdout=output, stderr=subprocess.STDOUT, check=True, timeout=600)
    return project


def add_netfox(work, netfox, project):
    if netfox is None:
        netfox = work / "netfox"
        subprocess.run(
            ["git", "clone", "--depth", "1", "--branch", NETFOX_TAG,
             "https://github.com/foxssake/netfox.git", str(netfox)], check=True,
        )
    revision = subprocess.check_output(["git", "-C", netfox, "rev-parse", "HEAD"], text=True).strip()
    if revision != NETFOX_REV:
        raise RuntimeError(f"Expected netfox {NETFOX_REV}, got {revision}")
    for name in ("netfox", "netfox.internals", "vest"):
        shutil.copytree(netfox / "addons" / name, project / "addons" / name)
    autoloads = [
        ("NetworkTime", "network-time.gd"),
        ("NetworkTimeSynchronizer", "network-time-synchronizer.gd"),
    ]
    settings = "".join(f'{name}="*res://addons/netfox/{path}"\n' for name, path in autoloads)
    config = project / "project.godot"
    config.write_text(config.read_text().replace("[autoload]\n", f"[autoload]\n\n{settings}", 1))
    match = project / "game/match/match.gd"
    source = match.read_text()
    signature = "func net_poses(poses: Dictionary[int, PackedFloat32Array], server_time: float) -> void:"
    if signature not in source:
        raise RuntimeError("The production pose RPC changed. Update the benchmark hook.")
    source = source.replace(signature, signature + "\n\tbenchmark_snapshot.emit(poses, server_time)", 1)
    match.write_text(source + "\n\nsignal benchmark_snapshot(poses: Dictionary, server_time: float)\n")


def percentile(values, fraction):
    ordered = sorted(values)
    return ordered[round((len(ordered) - 1) * fraction)]


def metrics(frames, fire_first, tracks=TRACKS):
    if len(frames) < 400:
        raise RuntimeError(f"Expected at least 400 observer frames, got {len(frames)}")
    result = {}
    phases = ("fire", "move") if fire_first else ("move", "fire")
    for name, first_leg in zip(phases, (0, 2)):
        result[name] = {}
        for column, track in enumerate(tracks, 1):
            speeds, lags = [], []
            longest_stop = 0.0
            for leg in range(first_leg, first_leg + 2):
                sign = 1 if leg % 2 == 0 else -1
                stop = 0.0
                for previous, frame in zip(frames, frames[1:]):
                    t = frame[0] - 2 * leg
                    if not 0.45 <= t <= 1.8:
                        continue
                    dt = frame[0] - previous[0]
                    velocity = sign * (frame[column] - previous[column]) / dt
                    ideal_x = SPEED * (t if sign == 1 else 2 - t)
                    lags.append(sign * (ideal_x - frame[column]) / SPEED * 1000)
                    speeds.append(velocity)
                    stop = stop + dt if abs(velocity) < 0.4 else 0.0
                    longest_stop = max(longest_stop, stop)
            result[name][track] = {
                "p95_speed_error": round(percentile([abs(v - SPEED) for v in speeds], 0.95), 2),
                "stopped_pct": round(100 * sum(abs(v) < 0.4 for v in speeds) / len(speeds), 1),
                "longest_stop_ms": round(longest_stop * 1000, 1),
                "lag_median_ms": round(statistics.median(lags), 1),
            }
    return result


def run(godot, project, out, profile, seed, native=False, blackout=False):
    out.mkdir()
    fire_first = seed % 2 == 0
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reserved:
        reserved.bind(("127.0.0.1", 0))
        server = reserved.getsockname()
    links = [Link(server, profile, seed + 2 * i) for i in range(2)]
    by_socket = {link.socket: link for link in links}
    queue, order = [], itertools.count()
    ports = [server[1], *(link.socket.getsockname()[1] for link in links)]
    with contextlib.ExitStack() as stack:
        for link in links:
            stack.enter_context(link.socket)
        processes = []
        try:
            for role, port in zip(ROLES, ports):
                log = stack.enter_context((out / f"{role}.log").open("w"))
                processes.append(subprocess.Popen(
                    [godot, "--headless", "--audio-driver", "Dummy", "--path", project,
                     "--log-file", out / f"{role}.engine.log", "--script", "res://tests/network_jitter/fixture.gd",
                     "--", role, out, str(port)], stdout=log, stderr=subprocess.STDOUT,
                ))
            deadline = time.monotonic() + 35
            started = False
            burst_start = float("inf")
            while time.monotonic() < deadline:
                if any(p.poll() is not None for p in processes):
                    raise RuntimeError(f"Godot exited early. See {out}")
                if not started and all((out / f"{role}.ready").exists() for role in ROLES):
                    fire_at = 0 if fire_first else 4
                    (out / "start").write_text(f"{time.time() + 8.0},{fire_at}")
                    if blackout:
                        burst_start = time.monotonic() + 8.55
                    started = True
                if all((out / f"{role}.done").exists() for role in ROLES):
                    break
                now = time.monotonic()
                while queue and queue[0][0] <= now:
                    _, _, sock, destination, packet = heapq.heappop(queue)
                    sock.sendto(packet, destination)
                delay = min(0.01, max(0.0, queue[0][0] - now)) if queue else 0.01
                for sock in select.select(list(by_socket), [], [], delay)[0]:
                    cutoff = burst_start + 0.5 if sock == links[0].socket and time.monotonic() >= burst_start else 0.0
                    by_socket[sock].receive(queue, order, cutoff)
            else:
                raise RuntimeError(f"Benchmark timed out. See {out}")
            (out / "finish").write_text("1")
            if any(p.wait(timeout=5) != 0 for p in processes):
                raise RuntimeError(f"Godot failed. See {out}")
        finally:
            for process in processes:
                if process.poll() is None:
                    process.kill()
                    process.wait()
    for role in ROLES:
        if "ERROR:" in (out / f"{role}.log").read_text():
            raise RuntimeError(f"Godot reported an error. See {out}")
    shots = int((out / "shots").read_text())
    if shots < 15:
        raise RuntimeError(f"Host accepted too few shots ({shots}). See {out}")
    frames = json.loads((out / "frames.json").read_text())
    tracks = TRACKS[:1] if native else TRACKS
    if any(max(frame[i] for frame in frames) - min(frame[i] for frame in frames) < 6
           for i in range(1, len(tracks) + 1)):
        raise RuntimeError(f"One of the tracks did not follow the player. See {out}")
    report = metrics(frames, fire_first, tracks)
    report.update(fire_first=fire_first, shots=shots, attempts=int((out / "attempts").read_text()),
                  rtt_ms=statistics.median(frame[4] for frame in frames),
                  total=sum(sum(link.total) for link in links),
                  dropped=sum(sum(link.dropped) for link in links))
    if native:
        authority = json.loads((out / "authority.json").read_text())
        report["authority"] = position_error(authority, 1)
        report["observer"] = position_error(frames, 1)
        if blackout:
            report["recovered_at_s"] = next(
                (round(row[0], 3) for row in authority if 1.05 <= row[0] <= 1.8 and
                 abs(row[1] - SPEED * row[0]) < 0.6), None,
            )
    (out / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


def position_error(rows, column):
    errors = [abs(row[column] - SPEED * (2 - abs(row[0] % 4 - 2))) for row in rows]
    return {"median_m": round(statistics.median(errors), 3), "p95_m": round(percentile(errors, 0.95), 3)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True, type=lambda p: Path(p).resolve())
    parser.add_argument("--out", required=True, type=lambda p: Path(p).resolve())
    parser.add_argument("--netfox", type=lambda p: Path(p).resolve())
    parser.add_argument("--profile", choices=PROFILES, action="append")
    parser.add_argument("--seed", type=int, action="append")
    parser.add_argument("--native", action="store_true")
    parser.add_argument("--blackout", action="store_true", help="Drop shooter uplink for 500 ms during the first leg")
    parser.add_argument("--source", type=lambda p: Path(p).resolve(), default=ROOT)
    args = parser.parse_args()
    if args.blackout and (not args.native or any(seed % 2 == 0 for seed in args.seed or ())):
        parser.error("--blackout requires --native and an odd --seed (movement first)")
    args.out.mkdir(parents=True)
    results = {}
    with tempfile.TemporaryDirectory(prefix="shooter-jitter-") as work:
        project = stage(Path(work), args.netfox, args.godot, args.out / "import.log", args.source, args.native)
        for name in args.profile or PROFILES:
            for seed in args.seed or ((11,) if args.blackout else (11, 28, 47, 64)):
                key = f"{name}-{seed}"
                print(key, flush=True)
                results[key] = run(args.godot, project, args.out / key, PROFILES[name], seed, args.native, args.blackout)
                (args.out / "summary.json").write_text(json.dumps(results, indent=2) + "\n")


if __name__ == "__main__":
    main()
