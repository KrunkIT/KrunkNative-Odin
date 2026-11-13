import contextlib
import io
import json
import socket
import struct
import unittest

from inspect_browser import CDP, Recorder, body_summary, header_summary, safe_url


class FakeCDP:
    def __init__(self):
        self.calls = []

    def send(self, method, params=None, session_id=""):
        self.calls.append((method, params, session_id))
        return len(self.calls)


class TracePrivacyTests(unittest.TestCase):
    def test_url_query_fragment_userinfo_and_challenge_path(self):
        value = safe_url("https://user:fixture-password@matchmaker.krunker.io/seek-game?game=NY%3A066nj&accessToken=fixture-token&captcha=fixture-proof#fixture-fragment")
        self.assertIn("game=NY%3A066nj", value)
        for secret in ("fixture-password", "fixture-token", "fixture-proof", "fixture-fragment"):
            self.assertNotIn(secret, value)
        self.assertNotIn("fixture-proof", safe_url("https://challenges.cloudflare.com/cdn-cgi/challenge-platform/h/b/fo/fixture-proof/another-proof"))
        self.assertNotIn("fixture-token", safe_url("data:text/plain,fixture-token"))

    def test_headers_preserve_proof_names_and_omit_values(self):
        headers = header_summary({"Authorization": "Bearer fixture-auth", "Cookie": "session=fixture-cookie; other=fixture-other",
                                  "Set-Cookie": "refresh=fixture-refresh; HttpOnly", "cf-chl": "fixture-proof",
                                  "custom-proof": "fixture-custom", "Content-Type": "application/json",
                                  "Referer": "https://krunker.io/?token=fixture-referrer"})
        encoded = json.dumps(headers)
        for secret in ("fixture-auth", "fixture-cookie", "fixture-other", "fixture-refresh", "fixture-proof", "fixture-custom", "fixture-referrer"):
            self.assertNotIn(secret, encoded)
        self.assertIn("custom-proof", headers)
        self.assertEqual(headers["Cookie"]["names"], ["session", "other"])
        self.assertEqual(headers["Content-Type"]["value"], "application/json")

    def test_json_form_and_opaque_body_values_stay_private(self):
        for body in ('{"username":"fixture-user","password":"fixture-password","nested":{"unfamiliarProof":"fixture-proof"},"list":["fixture-item"]}',
                     "username=fixture-user&password=fixture-password&unknown=fixture-proof", "fixture-opaque"):
            result = json.dumps(body_summary(body))
            for secret in ("fixture-user", "fixture-password", "fixture-proof", "fixture-item", "fixture-opaque"):
                self.assertNotIn(secret, result)
        self.assertEqual(body_summary('{"error":"CaptchaRequired"}')["error_code"], "CaptchaRequired")
        self.assertNotIn("error_code", body_summary('{"error":"fixture-secret"}'))

    def test_padded_plaintext_tokens_are_not_treated_as_form_field_names(self):
        for token in ("1794408279:" + "a" * 43 + "=", "a" * 43 + "=", "fixture-token=value"):
            for mime in ("", "text/plain", "text/plain; charset=utf-8"):
                result = body_summary(token, mime)
                self.assertEqual(result, {"bytes": len(token.encode()), "encoding": "opaque"})
        form = body_summary("username=fixture-user&password=fixture-password", "application/x-www-form-urlencoded; charset=utf-8")
        self.assertEqual(form["encoding"], "form")
        self.assertEqual([field["name"] for field in form["fields"]], ["username", "password"])
        self.assertNotIn("fixture-password", json.dumps(form))

    def test_network_correlation_body_shapes_storage_and_frames(self):
        output, cdp = io.StringIO(), FakeCDP()
        recorder = Recorder(output, cdp)
        with contextlib.redirect_stdout(io.StringIO()):
            recorder.consume({"method": "Network.requestWillBeSent", "params": {"requestId": "7", "request": {
                "method": "POST", "url": "https://matchmaker.krunker.io/seek-game?accessToken=fixture-token", "headers": {"Cookie": "session=fixture-cookie"},
                "postData": '{"captcha":"fixture-proof"}'}}})
            recorder.consume({"method": "Network.responseReceived", "params": {"requestId": "7", "response": {
                "url": "https://matchmaker.krunker.io/seek-game?accessToken=fixture-token", "status": 400, "mimeType": "application/json"}}})
            recorder.consume({"method": "Network.loadingFinished", "params": {"requestId": "7", "encodedDataLength": 27}})
            recorder.consume({"id": 1, "result": {"body": '{"error":"CaptchaRequired","access_token":"fixture-returned-token"}'}})
            recorder.consume({"method": "DOMStorage.domStorageItemAdded", "params": {"storageId": {"securityOrigin": "https://krunker.io"}, "key": "__FRVR_auth_access_token", "newValue": "fixture-storage-token"}})
            recorder.consume({"method": "Network.webSocketFrameSent", "params": {"requestId": "ws", "response": {"opcode": 1, "payloadData": "fixture-frame-secret"}}})
            recorder.consume({"method": "Runtime.consoleAPICalled", "params": {"type": "log", "args": [{"type": "string", "value": "fixture-console-secret"}]}})
        text = output.getvalue()
        for secret in ("fixture-token", "fixture-cookie", "fixture-proof", "fixture-returned-token", "fixture-storage-token", "fixture-frame-secret", "fixture-console-secret"):
            self.assertNotIn(secret, text)
        records = [json.loads(line) for line in text.splitlines()]
        self.assertEqual(records[3]["request_id"], "7")
        self.assertEqual(records[3]["body"]["error_code"], "CaptchaRequired")
        self.assertEqual(records[4]["key"], "__FRVR_auth_access_token")
        self.assertEqual(records[5]["payload_bytes"], len("fixture-frame-secret"))

    def test_cross_origin_frame_is_enabled_before_resume(self):
        output, cdp = io.StringIO(), FakeCDP()
        recorder = Recorder(output, cdp)
        with contextlib.redirect_stdout(io.StringIO()):
            recorder.consume({"method": "Target.attachedToTarget", "params": {"sessionId": "frame-session", "targetInfo": {"type": "iframe", "url": "https://challenges.cloudflare.com/"}}})
            self.assertNotIn("Runtime.runIfWaitingForDebugger", [call[0] for call in cdp.calls])
            recorder.consume({"id": 1, "result": {}})
            recorder.consume({"id": 2, "result": {}})
            recorder.consume({"id": 3, "result": {}})
        self.assertEqual(cdp.calls[-1], ("Runtime.runIfWaitingForDebugger", {}, "frame-session"))
        self.assertTrue(all(call[2] == "frame-session" for call in cdp.calls))
        self.assertFalse(recorder.session_pending)

    def test_request_ids_are_scoped_to_frame_session(self):
        output, cdp = io.StringIO(), FakeCDP()
        recorder = Recorder(output, cdp)
        with contextlib.redirect_stdout(io.StringIO()):
            for session, host in [("", "matchmaker.krunker.io"), ("iframe", "challenges.cloudflare.com")]:
                recorder.consume({"sessionId": session, "method": "Network.requestWillBeSent", "params": {"requestId": "same", "request": {"url": "https://" + host}}})
        self.assertEqual(len(recorder.requests), 2)


class CDPTransportTests(unittest.TestCase):
    def setUp(self):
        self.client, self.server = socket.socketpair()
        self.addCleanup(self.client.close)
        self.addCleanup(self.server.close)
        self.cdp = CDP.__new__(CDP)
        self.cdp.sock, self.cdp.buffer, self.cdp.fragment = self.client, bytearray(), bytearray()
        self.cdp.next_id = 0
        self.cdp.on_message = lambda message: None

    @staticmethod
    def frame(payload, first=0x81):
        length = len(payload)
        return bytes([first, length]) + payload if length < 126 else bytes([first, 126]) + struct.pack("!H", length) + payload

    def test_fragmented_messages_ping_and_buffered_frames(self):
        payload = b'{"method":"Network.loadingFinished","params":{"requestId":"42"}}'
        self.server.sendall(self.frame(payload[:10], 0x01) + self.frame(b"ping", 0x89) + self.frame(payload[10:], 0x80) + self.frame(b'{"id":2,"result":{}}'))
        self.assertEqual(self.cdp.receive()["params"]["requestId"], "42")
        self.assertEqual(self.cdp.receive()["id"], 2)
        pong = self.server.recv(64)
        self.assertEqual(pong[0], 0x8A)
        self.assertTrue(pong[1] & 128)

    def test_command_dispatches_events_before_matching_reply(self):
        seen = []
        self.cdp.on_message = seen.append
        self.server.sendall(self.frame(b'{"method":"Page.frameNavigated","params":{}}') + self.frame(b'{"id":1,"result":{"ready":true}}'))
        self.assertEqual(self.cdp.call("Network.enable"), {"ready": True})
        self.assertEqual(seen[0]["method"], "Page.frameNavigated")

    def test_oversized_frames_and_disconnect_fail_promptly(self):
        self.server.sendall(bytes([0x81, 127]) + struct.pack("!Q", 17 * 1024 * 1024))
        with self.assertRaises(RuntimeError):
            self.cdp.receive()
        self.cdp.buffer.clear()
        self.server.close()
        with self.assertRaises(EOFError):
            self.cdp.receive()


if __name__ == "__main__":
    unittest.main()
