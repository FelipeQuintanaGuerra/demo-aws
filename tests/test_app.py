import json
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "app"))

import app  # noqa: E402


class TestHandler(unittest.TestCase):
    def test_responde_200(self):
        respuesta = app.lambda_handler({}, None)
        self.assertEqual(respuesta["statusCode"], 200)

    def test_cuerpo_incluye_version(self):
        respuesta = app.lambda_handler({}, None)
        cuerpo = json.loads(respuesta["body"])
        self.assertEqual(cuerpo["version"], app.VERSION)
        self.assertIn("mensaje", cuerpo)


if __name__ == "__main__":
    unittest.main()
