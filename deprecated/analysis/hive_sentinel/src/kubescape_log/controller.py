from flask import Blueprint, jsonify
from src.kubescape_log.data.kubescape_reader import (
    fetch_kubescape_logs,
)

kubescape_bp = Blueprint("kubescape", __name__)


@kubescape_bp.route("/kubescape", methods=["GET"])
def get_kubescape_logs():
    try:
        logs = fetch_kubescape_logs()
        return jsonify(logs), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500
