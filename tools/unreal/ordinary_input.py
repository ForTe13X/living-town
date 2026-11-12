"""Bounded key pairs over a caller-authorized native input session.

No connection, tool selection, dispatch authorization, route or engine setter
lives here. The owner supplies transport and native observation validation,
owns session shutdown, and persists records only after input cleanup.
"""
from dataclasses import dataclass
import math
import time


class ObservationPending(RuntimeError):
    """A valid session has not produced its required later/settled sample yet."""


@dataclass(frozen=True)
class Limits:
    calls: int = 128
    cleanup_reserve: int = 8
    business_seconds: float = 70.0
    wall_seconds: float = 100.0
    pulse_seconds: float = 2.0

    def __post_init__(self):
        if type(self.calls) is not int or type(self.cleanup_reserve) is not int or not (8 < self.calls <= 128 and 8 <= self.cleanup_reserve < self.calls):
            raise ValueError("Invalid finite call budget")
        if not (0 < self.business_seconds <= 70 and self.business_seconds < self.wall_seconds <= 100 and 0 < self.pulse_seconds <= 2):
            raise ValueError("Invalid finite time budget")


class KeyPairs:
    KEYS = frozenset(("W", "A", "S", "D"))

    def __init__(self, call, validate_snapshot, *, limits=Limits(),
                 supervise=lambda: None, clock=time.monotonic, sleep=time.sleep):
        self.transport = call
        self.validate_snapshot = validate_snapshot
        self.limits = limits
        self.supervise = supervise
        self.clock, self.sleep = clock, sleep
        self.started = clock()
        self.held = set()
        self.records = []
        self.pulse_deadline = None

    def _budget(self, cleanup=False):
        elapsed = self.clock() - self.started
        seconds = self.limits.wall_seconds if cleanup else self.limits.business_seconds
        calls = self.limits.calls if cleanup else self.limits.calls - self.limits.cleanup_reserve
        if not math.isfinite(elapsed) or not 0 <= elapsed < seconds or len(self.records) >= calls:
            raise ValueError("Finite input budget exhausted; cleanup remains bounded")
        return min(15.0, seconds - elapsed)

    def _call(self, method, arguments=None, *, cleanup=False):
        if method not in ("submit_key", "read_snapshot"):
            raise ValueError("Only fixed ordinary key/read callbacks are supported")
        self.supervise()
        timeout = self._budget(cleanup)
        if not cleanup and self.pulse_deadline is not None:
            remaining = self.pulse_deadline - self.clock()
            if not math.isfinite(remaining) or remaining <= 0:
                raise ValueError("Pulse deadline exhausted before transport")
            timeout = min(timeout, remaining)
        row = dict(method=method, arguments=arguments or {}, elapsed=self.clock() - self.started)
        self.records.append(row)
        try:
            response = self.transport(method, row["arguments"], timeout)
            if not isinstance(response, dict) or response.get("status") in ("FAILED", "REFUSED"):
                raise ValueError("Native input transport refused")
            row["actual"] = response
            return response
        except BaseException as error:
            row["error"] = repr(error)
            raise

    def _observe(self, after, settled):
        for attempt in range(4):
            snapshot = self._call("read_snapshot")
            try:
                if self.validate_snapshot(snapshot, after, frozenset(self.held), settled) is not True:
                    raise ValueError("Owner did not validate the native observation")
                return snapshot
            except ObservationPending:
                if attempt == 3:
                    raise
                self.sleep(0.06)

    def release_owned(self):
        for key in tuple(self.held):
            receipt = self._call("submit_key", dict(key_name=key, event_name="release"), cleanup=True)
            self._submission_frame(receipt)
            self.held.remove(key)

    @staticmethod
    def _submission_frame(receipt):
        frame = receipt.get("submitted_frame")
        if (receipt.get("status") != "ORDINARY_INPUT_SUBMITTED_NOT_DISPATCH_ACK"
                or receipt.get("dispatch_ack_claimed") is not False
                or type(frame) is not int or frame < 0):
            raise ValueError("A typed input submission receipt is required")
        return frame

    def pulse(self, key, seconds):
        if type(key) is not str or key not in self.KEYS or type(seconds) not in (int, float) or not math.isfinite(seconds) or not 0.018 <= seconds <= 1.4:
            raise ValueError("Only a bounded ordinary WASD hold is supported")
        if self.held:
            raise ValueError("Finish the owned key pair before starting another")
        self._budget()
        started = self.clock()
        self.pulse_deadline = started + self.limits.pulse_seconds
        press = None
        held_observation = None
        self.held.add(key)
        try:
            try:
                press = self._call("submit_key", dict(key_name=key, event_name="press"))
                self._submission_frame(press)
                if seconds >= 0.25:
                    self.sleep(0.035)
                    held_observation = self._observe(int(press["submitted_frame"]), False)
                    self.sleep(max(0.0, seconds - (self.clock() - started)))
                else:
                    self.sleep(max(0.018, seconds - (self.clock() - started)))
            finally:
                release = self._call("submit_key", dict(key_name=key, event_name="release"), cleanup=True)
                self._submission_frame(release)
                self.held.remove(key)
            if press is None or int(release["submitted_frame"]) <= int(press["submitted_frame"]):
                raise ValueError("A same-frame tap cannot prove an ordinary held pair")
            self.sleep(0.035)
            released = self._observe(int(release["submitted_frame"]), True)
            if self.clock() - started >= self.limits.pulse_seconds:
                raise ValueError("Pulse exceeded its original two-second bound")
            return dict(press=press, release=release, held_observation=held_observation, released_observation=released)
        finally:
            self.pulse_deadline = None
