import json
import os

import azure.functions as func
import requests

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)


def _presidio_analyze(text: str) -> dict:
    presidio_url = os.getenv("PRESIDIO_API_URL", "").strip()
    timeout_seconds = int(os.getenv("PRESIDIO_TIMEOUT_SECONDS", "10"))

    if not presidio_url:
        raise RuntimeError("PRESIDIO_API_URL is not configured")

    response = requests.post(
        presidio_url,
        json={"text": text},
        timeout=timeout_seconds,
    )
    response.raise_for_status()
    return response.json()


@app.route(route="demo/process", methods=["POST"])
def process_request(req: func.HttpRequest) -> func.HttpResponse:
    try:
        body = req.get_json()
    except ValueError:
        return func.HttpResponse(
            json.dumps({"status": "error", "message": "Request body must be valid JSON."}),
            status_code=400,
            mimetype="application/json",
        )

    text = body.get("text") if isinstance(body, dict) else None
    if not isinstance(text, str) or not text.strip():
        return func.HttpResponse(
            json.dumps({"status": "error", "message": "Field 'text' is required."}),
            status_code=400,
            mimetype="application/json",
        )

    try:
        analysis = _presidio_analyze(text)
    except requests.RequestException as ex:
        return func.HttpResponse(
            json.dumps(
                {
                    "status": "error",
                    "message": "Presidio API call failed.",
                    "detail": str(ex),
                }
            ),
            status_code=502,
            mimetype="application/json",
        )
    except RuntimeError as ex:
        return func.HttpResponse(
            json.dumps({"status": "error", "message": str(ex)}),
            status_code=500,
            mimetype="application/json",
        )

    if analysis.get("has_pii") is True:
        return func.HttpResponse(
            json.dumps(
                {
                    "status": "rejected",
                    "message": "PII detected in request payload.",
                    "findings": analysis.get("findings", []),
                }
            ),
            status_code=400,
            mimetype="application/json",
        )

    return func.HttpResponse(
        json.dumps(
            {
                "status": "accepted",
                "message": "No PII was detected.",
                "text": text,
            }
        ),
        status_code=200,
        mimetype="application/json",
    )
