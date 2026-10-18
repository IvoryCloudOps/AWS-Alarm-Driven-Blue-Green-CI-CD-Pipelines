import os

from flask import Flask, jsonify

app = Flask(__name__)

# Set by the Jenkins SIMULATE_BAD_RELEASE parameter to rehearse a failed deployment.
SIMULATE_UNHEALTHY = os.environ.get("SIMULATE_UNHEALTHY") == "true"


@app.route("/")
def home():
    return """
    IvoryCloud Delivery Platform
    Application Version: v1.0.0
    Status: Healthy
    """


@app.route("/health")
def health():
    if SIMULATE_UNHEALTHY:
        return jsonify(status="unhealthy", version="1.0.0"), 500

    return jsonify(
        status="healthy",
        version="1.0.0"
    ), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)