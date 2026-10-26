import importlib.util
import json
from pathlib import Path
import unittest

import azure.functions as func

SOURCE = Path(__file__).resolve().parents[1] / "src/demo-api/function_app.py"
SPEC = importlib.util.spec_from_file_location("demo_api", SOURCE)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
FUNCTION = MODULE.app.get_functions()[0]
ACCEPT_MESSAGE = FUNCTION.get_user_function()


class DemoApiTests(unittest.TestCase):
    def post(self, body: bytes) -> func.HttpResponse:
        request = func.HttpRequest(
            method="POST",
            url="http://localhost/api/customer-support/messages",
            headers={"Content-Type": "application/json"},
            body=body,
        )
        return ACCEPT_MESSAGE(request)

    def test_route(self) -> None:
        binding = FUNCTION.get_bindings_dict()["bindings"][0]
        self.assertEqual(binding["route"], "customer-support/messages")

    def test_accepts_messages_without_dependency_calls(self) -> None:
        for text in ["hello world", "アプリの設定を教えてください。", "test.person@example.com"]:
            with self.subTest(text=text):
                response = self.post(json.dumps({"text": text}).encode())
                self.assertEqual(response.status_code, 200)
                self.assertEqual(
                    json.loads(response.get_body()),
                    {"status": "accepted", "message": "Message accepted.", "text": text},
                )

    def test_rejects_invalid_input(self) -> None:
        for body in [b"", b"{", b"{}", b"[]", b"null", b'{"text":null}',
                     b'{"text":123}', b'{"text":""}', b'{"text":" \\n\\t"}']:
            with self.subTest(body=body):
                response = self.post(body)
                self.assertEqual(response.status_code, 400)
                self.assertEqual(json.loads(response.get_body())["status"], "error")


if __name__ == "__main__":
    unittest.main()
