import json
import re
import azure.functions as func
from presidio_analyzer import Pattern, PatternRecognizer

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)


EMAIL_RECOGNIZER = PatternRecognizer(
    supported_entity="EMAIL_ADDRESS",
    patterns=[
        Pattern(name="email", regex=r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", score=0.8),
    ],
)

PHONE_RECOGNIZER = PatternRecognizer(
    supported_entity="PHONE_NUMBER",
    patterns=[
        Pattern(name="jp_phone", regex=r"(?:0\d{1,4}-\d{1,4}-\d{4}|0\d{9,10})", score=0.8),
    ],
)

CARD_RECOGNIZER = PatternRecognizer(
    supported_entity="CREDIT_CARD",
    patterns=[
        Pattern(name="card", regex=r"(?:\d[ -]*?){13,16}", score=0.6),
    ],
)


def _collect_findings(text: str) -> list[dict]:
    findings = []
    for recognizer in [EMAIL_RECOGNIZER, PHONE_RECOGNIZER, CARD_RECOGNIZER]:
        for result in recognizer.analyze(text=text, entities=[recognizer.supported_entities[0]], nlp_artifacts=None):
            findings.append(
                {
                    "entity_type": result.entity_type,
                    "start": result.start,
                    "end": result.end,
                    "score": result.score,
                    "text": text[result.start:result.end],
                }
            )

    # Lightweight my-number style check using regex to keep dependencies small.
    for match in re.finditer(r"\b\d{4}-\d{4}-\d{4}\b", text):
        findings.append(
            {
                "entity_type": "NATIONAL_ID",
                "start": match.start(),
                "end": match.end(),
                "score": 0.7,
                "text": match.group(0),
            }
        )

    findings.sort(key=lambda f: (f["start"], -f["end"]))
    return findings


@app.route(route="pii-filter/analyze", methods=["POST"])
def presidio_analyze(req: func.HttpRequest) -> func.HttpResponse:
    try:
        body = req.get_json()
    except ValueError:
        return func.HttpResponse(
            json.dumps({"error": "Request body must be valid JSON."}),
            status_code=400,
            mimetype="application/json",
        )

    text = body.get("text") if isinstance(body, dict) else None
    if not isinstance(text, str) or not text.strip():
        return func.HttpResponse(
            json.dumps({"error": "Field 'text' is required."}),
            status_code=400,
            mimetype="application/json",
        )

    findings = _collect_findings(text)
    response = {
        "text": text,
        "has_pii": len(findings) > 0,
        "findings": findings,
    }

    return func.HttpResponse(json.dumps(response), status_code=200, mimetype="application/json")
