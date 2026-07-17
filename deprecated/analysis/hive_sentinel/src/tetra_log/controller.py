from flask import Blueprint, jsonify
from src.tetra_log.reader import fetch_tetragon_logs

tetra_bp = Blueprint("tetragon", __name__)


@tetra_bp.route("/tetragon", methods=["GET"])
def get_tetragon_logs():
    try:
        logs = fetch_tetragon_logs()
        return jsonify(logs), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500
