from pathlib import Path
import re
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
POLICY = ET.parse(ROOT / "infra/policies/customer-support.xml").getroot()
SCREENING = POLICY.find("inbound/choose/when[@condition='@(!context.Request.Url.Query.ContainsKey(\"no-pii-filter\"))']")


class ApimPolicyTests(unittest.TestCase):
    def test_same_japanese_question_as_direct_test(self) -> None:
        body = SCREENING.find("send-request/set-body").text
        script = (ROOT / "tests/06_test_decision1-jp.sh").read_text()
        for key in ["instructions", "pii", "no_pii"]:
            with self.subTest(key=key):
                actual = re.search(r'new JProperty\("' + key + r'", "([^"]*)"\)', body)
                expected = re.search(key + r': "([^"]*)"', script)
                self.assertIsNotNone(actual)
                self.assertIsNotNone(expected)
                self.assertEqual(actual.group(1), expected.group(1))

    def test_uses_managed_identity_only_for_decision_request(self) -> None:
        identities = POLICY.findall(".//authentication-managed-identity")
        self.assertEqual(len(identities), 1)
        self.assertIs(
            identities[0],
            SCREENING.find("send-request/authentication-managed-identity"),
        )
        self.assertEqual(identities[0].get("resource"), "https://cognitiveservices.azure.com")
        self.assertEqual(SCREENING.find("send-request").get("timeout"), "20")

    def test_bypass_only_skips_screening(self) -> None:
        inbound = POLICY.find("inbound")
        gate = inbound.findall("choose")[1]
        self.assertEqual(list(gate), [SCREENING])
        self.assertEqual(len(POLICY.findall(".//send-request")), 1)
        self.assertIsNotNone(SCREENING.find("send-request"))
        self.assertIsNotNone(SCREENING.find("set-variable[@name='piiChoice']"))
        self.assertLess(
            list(inbound).index(inbound.find("set-variable[@name='requestText']")),
            list(inbound).index(gate),
        )
        self.assertLess(list(inbound).index(inbound.findall("choose")[0]), list(inbound).index(gate))
        self.assertGreater(list(inbound).index(inbound.find("set-body")), list(inbound).index(gate))

    def test_input_parse_errors_are_bad_requests(self) -> None:
        parser = POLICY.find("inbound/set-variable[@name='requestText']")
        self.assertEqual(parser.get("id"), "validate-input")
        when = POLICY.find("on-error/choose/when")
        self.assertIn("validate-input", when.get("condition"))
        self.assertEqual(when.find("return-response/set-status").get("code"), "400")

    def test_only_allowlisted_text_is_forwarded(self) -> None:
        inbound = POLICY.find("inbound")
        rewrite = inbound.find("rewrite-uri")
        self.assertEqual(rewrite.get("template"), "/api/customer-support/messages")
        self.assertEqual(rewrite.get("copy-unmatched-params"), "false")
        body = inbound.find("set-body").text
        self.assertIn('new JProperty("text", (string)context.Variables["requestText"])', body)

    def test_dependency_and_unknown_answer_fail_closed(self) -> None:
        gates = SCREENING.findall("choose")
        self.assertIn("StatusCode != 200", gates[0].find("when").get("condition"))
        self.assertEqual(gates[0].find("when/return-response/set-status").get("code"), "502")
        decisions = gates[1].findall("when")
        self.assertIn('== "pii"', decisions[0].get("condition"))
        self.assertEqual(decisions[0].find("return-response/set-status").get("code"), "400")
        self.assertIn('!= "no_pii"', decisions[1].get("condition"))
        self.assertEqual(decisions[1].find("return-response/set-status").get("code"), "502")
        self.assertEqual(POLICY.find("on-error/return-response/set-status").get("code"), "502")


if __name__ == "__main__":
    unittest.main()
