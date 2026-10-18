import os

from flask import Flask, jsonify

app = Flask(__name__)

# Set by the Jenkins FAULT_INJECTION parameter to rehearse failed deployments:
#   unhealthy   - /health returns 500, so green never receives production traffic
#   http-errors - /health passes, but / returns 500 once traffic shifts to green
FAULT_INJECTION = os.environ.get("FAULT_INJECTION", "none")


@app.route("/")
def home():
    if FAULT_INJECTION == "http-errors":
        return "Simulated application error\n", 500

    return """
    IvoryCloud Delivery Platform
    Application Version: v1.0.0
    Status: Healthy
    """


@app.route("/health")
def health():
    if FAULT_INJECTION == "unhealthy":
        return jsonify(status="unhealthy", version="1.0.0"), 500

    return jsonify(
        status="healthy",
        version="1.0.0"
    ), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)