import json

import azure.functions as func

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)


@app.route(route="customer-support/messages", methods=["POST"])
def accept_message(req: func.HttpRequest) -> func.HttpResponse:
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

    return func.HttpResponse(
        json.dumps(
            {
                "status": "accepted",
                "message": "Message accepted.",
                "text": text,
            }
        ),
        status_code=200,
        mimetype="application/json",
    )
