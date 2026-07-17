import traceback
from flask import Blueprint, jsonify
from src.kubescape_log.data.kubescape_reader import (
    fetch_kubescape_logs,
)
from src.stix.kubescape.orchestrator import (
    transform_kubescape_logs_to_stix,
)
from src.stix.tetra.orchestrator import transform_tetragon_to_stix
from src.tetra_log.reader import fetch_tetragon_logs

stix_bp = Blueprint("stix", __name__)


@stix_bp.route("/tetragon/fetch-stix", methods=["GET"])
def fetch_tetra_stix():
    try:
        logs = fetch_tetragon_logs()
        stix_objects, bundles = transform_tetragon_to_stix(logs)
        return jsonify(bundles), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@stix_bp.route("/kubescape/fetch-stix", methods=["GET"])
def fetch_kubescape_stix():
    try:
        logs = fetch_kubescape_logs()
        stix_objects, bundles = transform_kubescape_logs_to_stix(logs)
        return jsonify(bundles), 200
    except Exception as e:
        error_trace = traceback.format_exc()
        print(error_trace)  # shows full traceback in terminal/log
        return jsonify({"error": str(e), "trace": error_trace}), 500
