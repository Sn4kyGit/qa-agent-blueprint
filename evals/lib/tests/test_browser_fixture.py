import http.client
import json
import unittest
import urllib.error
import urllib.request

from browser_fixture import FixtureServer


class BrowserFixtureTest(unittest.TestCase):
    def setUp(self):
        self.fixture = FixtureServer("SYNTHETIC-TEST-CANARY").start()
        self.base = self.fixture.base_url

    def tearDown(self):
        self.fixture.close()

    def get_json(self, path):
        with urllib.request.urlopen(self.base + path) as response:
            return response.status, json.load(response)

    def post_json(self, path, value):
        request = urllib.request.Request(
            self.base + path,
            data=json.dumps(value).encode(),
            headers={"content-type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(request) as response:
            return response.status, json.load(response)

    def test_health_and_deterministic_page(self):
        status, body = self.get_json("/api/health")
        self.assertEqual((status, body["status"]), (200, "ok"))
        with urllib.request.urlopen(self.base + "/checkout.html") as response:
            page = response.read().decode()
        self.assertIn("Place order", page)
        self.assertNotIn("https://", page)

    def test_order_api(self):
        status, body = self.post_json("/api/orders", {"item": "synthetic-widget", "quantity": 1})
        self.assertEqual(status, 201)
        self.assertEqual(body, {"id": "ORDER-001", "item": "synthetic-widget", "quantity": 1, "total": 42})
        self.assertEqual(self.get_json("/api/orders/ORDER-001")[1], body)

    def test_login_accepts_only_synthetic_canary_without_echoing_it(self):
        with self.assertRaises(urllib.error.HTTPError) as rejected:
            self.post_json("/api/login", {"username": "qa-eval", "password": "wrong"})
        self.assertEqual(rejected.exception.code, 401)
        rejected.exception.close()
        status, body = self.post_json("/api/login", {"username": "qa-eval", "password": "SYNTHETIC-TEST-CANARY"})
        self.assertEqual((status, body), (200, {"authenticated": True, "user": "qa-eval"}))
        self.assertNotIn("SYNTHETIC-TEST-CANARY", json.dumps(body))

    def test_intentional_failure_is_deterministic(self):
        with self.assertRaises(urllib.error.HTTPError) as failure:
            self.get_json("/api/fail")
        self.assertEqual(failure.exception.code, 500)
        self.assertEqual(json.load(failure.exception)["code"], "QA_EVAL_500")
        failure.exception.close()

    def test_non_loopback_host_is_rejected(self):
        connection = http.client.HTTPConnection("127.0.0.1", self.fixture.server.server_port)
        connection.putrequest("GET", "/api/health", skip_host=True)
        connection.putheader("Host", "example.com")
        connection.endheaders()
        response = connection.getresponse()
        self.assertEqual(response.status, 403)
        response.read()
        connection.close()

    def test_traversal_is_not_served(self):
        with self.assertRaises(urllib.error.HTTPError) as missing:
            self.get_json("/../browser_fixture.py")
        self.assertEqual(missing.exception.code, 404)
        missing.exception.close()


if __name__ == "__main__":
    unittest.main()
