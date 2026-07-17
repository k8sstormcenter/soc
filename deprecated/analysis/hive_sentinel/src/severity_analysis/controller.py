from flask import Blueprint, jsonify
from src.severity_analysis.analyzer import analyze_severity
from src.severity_analysis.reader import get_bundle

analysis_bp = Blueprint("analysis", __name__)


@analysis_bp.route("/fetch-bundle", methods=["GET"])
def get_kubescape_logs():
    try:
        logs = get_bundle()
        result = [
            {"severity": analyze_severity(bundle), "bundle": bundle} for bundle in logs
        ]
        return jsonify(result), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500
