import json
import time
import traceback
from uuid import uuid4
from flask import Blueprint, request, jsonify
from src.etl.pattern_matcher.etl import PatternMatcherETL

pattern_bp = Blueprint("pattern_matcher", __name__, url_prefix="/pattern-matcher")

running_matchers = {}

@pattern_bp.route("/start", methods=["POST"])
def start_pattern_etl():
    data = request.json

    timestamp = data.get("timestamp")
    podname = data.get("pod")
    namespace = data.get("namespace")

    try:
        matcher = PatternMatcherETL()
        matcher.set_filters(timestamp, podname, namespace)
        matcher.start()

        matcher_id = str(uuid4())
        running_matchers[matcher_id] = {
            "etl": matcher,
            "params": {
                "timestamp": timestamp,
                "pod": podname,
                "namespace": namespace
            }
        }

        return jsonify({
            "status": "started",
            "uuid": matcher_id,
            "params": {
                "timestamp": timestamp,
                "pod": podname,
                "namespace": namespace
            }
        }), 200

    except Exception as e:
        traceback.print_exc()
        return jsonify({"status": "error", "message": str(e)}), 500


@pattern_bp.route("/stop", methods=["POST"])
def stop_pattern_etl():
    data = request.json
    matcher_id = data.get("uuid")

    if matcher_id not in running_matchers:
        return jsonify({"status": "error", "message": f"No matcher found with uuid {matcher_id}"}), 404

    matcher = running_matchers[matcher_id]["etl"]
    matcher.stop()
    del running_matchers[matcher_id]

    return jsonify({"status": "stopped", "uuid": matcher_id}), 200


@pattern_bp.route("/status", methods=["GET"])
def status_pattern_etls():
    try:
        status = {}
        for matcher_id, info in running_matchers.items():
            etl = info["etl"]
            status[matcher_id] = {
                "running": etl.is_running(),
                "params": info["params"]
            }
        return jsonify({"running_matchers": status}), 200
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500
