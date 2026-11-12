"""No-engine regressions for timing, cleanup and transcript persistence."""
import copy
import json
from pathlib import Path
import unittest
from unittest.mock import patch

from ordinary_input import KeyPairs, Limits, ObservationPending
from mcp_client import Client


class Frames:
    def __init__(self, latency=0.016, inline_persist=0.0):
        self.now = 0.0
        self.next_tick = 1 / 60
        self.frame = 0
        self.velocity = self.position = 0.0
        self.latency, self.inline_persist = latency, inline_persist
        self.pending = []
        self.stock = set()
        self.events = []
        self.methods = []

    def sleep(self, seconds):
        end = self.now + seconds
        while self.next_tick <= end + 1e-9:
            self.now = self.next_tick
            self.frame += 1
            for key, event in self.pending:
                if event == "press":
                    self.stock.add(key)
                else:
                    self.stock.discard(key)
            self.pending.clear()
            target = 106.13712295889874 if self.stock else 0.0
            if target:
                self.velocity += min(2048 / 60, target - self.velocity)
            else:
                self.velocity = max(0.0, self.velocity * (1 - 16 / 60) - 2048 / 60)
            self.position += self.velocity / 60
            self.next_tick += 1 / 60
        self.now = end

    def call(self, method, args, timeout):
        self.methods.append((method, args, timeout))
        self.sleep(self.latency / 2)
        if method == "submit_key":
            self.pending.append((args["key_name"], args["event_name"]))
            self.events.append((args["event_name"], self.frame))
            result = dict(status="ORDINARY_INPUT_SUBMITTED_NOT_DISPATCH_ACK", submitted_frame=self.frame, dispatch_ack_claimed=False)
        else:
            assert method == "read_snapshot"
            result = dict(status="SNAPSHOT", frame=self.frame, stock=sorted(self.stock), speed=self.velocity)
        self.sleep(self.latency / 2)
        self.sleep(self.inline_persist)
        return result

    def validate(self, snapshot, after, held, settled):
        if snapshot["frame"] <= after or (settled and snapshot["speed"] > 2):
            raise ObservationPending("Await natural released/settled frame")
        if set(snapshot["stock"]) != set(held):
            raise ValueError("Actual stock ownership mismatch")
        return True

    def controller(self):
        return KeyPairs(self.call, self.validate, clock=lambda: self.now, sleep=self.sleep)


class InputCases(unittest.TestCase):
    def test_fine_pairs_release_before_read_and_avoid_old_quantum(self):
        frames = []
        for latency in (0.0, 0.016, 0.032, 0.047):
            model = Frames(latency)
            control = model.controller()
            result = control.pulse("D", 0.03)
            self.assertIsNone(result["held_observation"])
            self.assertEqual([x[0] for x in model.methods[:3]], ["submit_key", "submit_key", "read_snapshot"])
            count = model.events[1][1] - model.events[0][1]
            self.assertGreater(count, 0)
            self.assertLess(count, 7)
            self.assertFalse(control.held)
            self.assertFalse(model.stock)
            self.assertLessEqual(result["released_observation"]["speed"], 2)
            frames.append(count)
        old = Frames(0.016, inline_persist=0.03)
        start = old.now
        old.call("submit_key", dict(key_name="D", event_name="press"), 15)
        old.sleep(0.035)
        old.call("read_snapshot", {}, 15)
        old.sleep(0.02)  # Prior full waypoint history persisted while held.
        old.sleep(max(0.0, 0.03 - (old.now - start)))
        old.call("submit_key", dict(key_name="D", event_name="release"), 15)
        old_frames = old.events[1][1] - old.events[0][1]
        self.assertGreaterEqual(old_frames, 7)
        self.assertLessEqual(old_frames, 11)
        self.assertLess(max(frames), old_frames)

    def test_observer_failure_releases_owned_coarse_key(self):
        model = Frames()

        def refuse(*args):
            raise ValueError("Lost source/session")

        control = KeyPairs(model.call, refuse, clock=lambda: model.now, sleep=model.sleep)
        with self.assertRaisesRegex(ValueError, "Lost source/session"):
            control.pulse("W", 0.5)
        self.assertEqual(model.events[-1][0], "release")
        self.assertFalse(control.held)

    def test_failed_press_response_still_attempts_release(self):
        model = Frames()

        def call(method, args, timeout):
            answer = model.call(method, args, timeout)
            if args.get("event_name") == "press":
                raise OSError("Reply lost after submit")
            return answer

        control = KeyPairs(call, model.validate, clock=lambda: model.now, sleep=model.sleep)
        with self.assertRaises(OSError):
            control.pulse("W", 0.03)
        self.assertEqual(model.events[-1][0], "release")
        self.assertFalse(control.held)

    def test_invalid_input_and_budget_never_send_press(self):
        model = Frames()
        control = model.controller()
        for key, duration in (("E", 0.03), ("W", float("nan")), ("W", 0.001), ("W", 2.0)):
            with self.assertRaises(ValueError):
                control.pulse(key, duration)
        control.records = [{}] * 120
        with self.assertRaises(ValueError):
            control.pulse("W", 0.03)
        self.assertFalse(model.events)
        with self.assertRaises(ValueError):
            Limits(calls=129)
        with self.assertRaises(ValueError):
            Limits(cleanup_reserve=2)
        with self.assertRaises(ValueError):
            control._call("call_tool", {"tool_name": "arbitrary"})
        self.assertFalse(model.events)

    def test_malformed_release_retains_ownership_for_cleanup_retry(self):
        for bad in (dict(status="QUEUED"), dict(status="ORDINARY_INPUT_SUBMITTED_NOT_DISPATCH_ACK", submitted_frame=True, dispatch_ack_claimed=False)):
            model = Frames()
            first = True

            def call(method, args, timeout):
                nonlocal first
                if args.get("event_name") == "release" and first:
                    first = False
                    return bad  # Refused to submit, so native key is still down.
                return model.call(method, args, timeout)

            control = KeyPairs(call, model.validate, clock=lambda: model.now, sleep=model.sleep)
            with self.assertRaisesRegex(ValueError, "typed input submission"):
                control.pulse("W", 0.03)
            self.assertEqual(control.held, {"W"})
            self.assertIn("W", model.stock)
            self.assertIsNone(control.pulse_deadline)
            control.release_owned()
            model.sleep(0.035)
            self.assertFalse(control.held)
            self.assertFalse(model.stock)

    def test_pulse_timeout_caps_blocking_work_but_preserves_release_cleanup(self):
        model = Frames()
        timeouts = []

        def call(method, args, timeout):
            timeouts.append((args.get("event_name"), timeout))
            if args.get("event_name") == "press":
                model.call(method, args, timeout)
                model.sleep(timeout)
                raise TimeoutError("No reply within pulse budget")
            return model.call(method, args, timeout)

        control = KeyPairs(call, model.validate, clock=lambda: model.now, sleep=model.sleep)
        with self.assertRaises(TimeoutError):
            control.pulse("W", 0.03)
        self.assertLessEqual(timeouts[0][1], 2)
        self.assertEqual(timeouts[1][0], "release")
        self.assertLessEqual(timeouts[1][1], 15)
        self.assertFalse(control.held)
        self.assertIsNone(control.pulse_deadline)

    def test_supervision_time_rechecked_before_operational_transport(self):
        model = Frames()
        control = KeyPairs(model.call, model.validate, supervise=lambda: model.sleep(3), clock=lambda: model.now, sleep=model.sleep)
        with self.assertRaisesRegex(ValueError, "Pulse deadline exhausted"):
            control.pulse("W", 0.03)
        self.assertEqual([args["event_name"] for method, args, timeout in model.methods], ["release"])
        self.assertFalse(control.held)
        self.assertIsNone(control.pulse_deadline)

    def test_slow_transport_stops_with_release(self):
        model = Frames(0.6)
        control = model.controller()
        with self.assertRaises(ValueError):
            control.pulse("W", 1.4)
        self.assertEqual(model.events[-1][0], "release")
        self.assertFalse(control.held)
        self.assertLess(len(model.methods), 10)


class TranscriptCases(unittest.TestCase):
    def test_actual_client_defers_exact_responses_and_keeps_supervision(self):
        writes, guards, requests = [], [], []

        class Response:
            status = 200
            headers = {"Content-Type": "application/json", "Mcp-Session-Id": "inert"}

            def __init__(self, request):
                self.body = json.dumps(dict(jsonrpc="2.0", id=json.loads(request.data)["id"], result={})).encode()

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            def read(self, limit):
                return self.body[:limit]

        def open_inert(request, timeout):
            requests.append(timeout)
            return Response(request)

        with patch("urllib.request.urlopen", open_inert), patch("mcp_client.write", lambda p, v: writes.append(copy.deepcopy(v))):
            client = Client(Path("."), lambda: guards.append(True), "http://127.0.0.1:24681/mcp")
            client.defer_history_persistence = True
            client.request("tools/list", request_timeout=0.1)
            client.request("tools/list", request_timeout=0.2)
            self.assertFalse(writes)
            client.defer_history_persistence = False
            client.flush_history()
            self.assertEqual(len(writes[0]), 2)
            client.request("tools/list")
            self.assertEqual(len(writes[-1]), 3)
            self.assertEqual(len(guards), 6)
            for timeout in (0, -1, 16, float("nan")):
                with self.assertRaises(ValueError):
                    client.request("tools/list", request_timeout=timeout)
        for actual, maximum in zip(requests, (0.1, 0.2, 15), strict=True):
            self.assertGreater(actual, 0)
            self.assertLessEqual(actual, maximum)

    def test_combined_client_rechecks_deadline_after_its_supervision(self):
        model = Frames()
        submitted = []

        class Response:
            status = 200
            headers = {"Content-Type": "application/json"}

            def __init__(self, request, timeout):
                value = json.loads(request.data)
                args = value["params"]
                submitted.append((args["event_name"], model.now, timeout))
                answer = model.call("submit_key", args, timeout)
                self.body = json.dumps(dict(jsonrpc="2.0", id=value["id"], result=answer)).encode()

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            def read(self, limit):
                return self.body[:limit]

        with patch("mcp_client.time.monotonic", lambda: model.now), patch("urllib.request.urlopen", Response):
            client = Client(Path("."), lambda: model.sleep(3), "http://127.0.0.1:24681/mcp")
            client.defer_history_persistence = True
            control = KeyPairs(lambda method, args, timeout: client.request(method, args, request_timeout=timeout),
                               model.validate, clock=lambda: model.now, sleep=model.sleep)
            with self.assertRaisesRegex(ValueError, "Request deadline exhausted before transport"):
                control.pulse("W", 0.03)
        self.assertEqual([event for event, _, _ in submitted], ["release"])
        self.assertLessEqual(submitted[0][2], 12)
        self.assertFalse(control.held)
        self.assertFalse(model.stock)
        self.assertIsNone(control.pulse_deadline)


if __name__ == "__main__":
    unittest.main()
