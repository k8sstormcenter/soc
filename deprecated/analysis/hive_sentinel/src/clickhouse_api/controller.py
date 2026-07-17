from flask import Blueprint, request, jsonify
import traceback
from src.clickhouse_api.service import DataService

data_bp = Blueprint('data_bp', __name__)
data_service = DataService()

def handle_request(service_method):
    try:
        filters = request.args.to_dict()
        limit = filters.pop('limit', 100)
        data = service_method(filters, limit)
        return jsonify(data), 200
    except Exception as e:
        traceback.print_exc()
        return jsonify({"status": "error", "message": str(e)}), 500

@data_bp.route('/http_events', methods=['GET'])
def get_http_events():
    return handle_request(data_service.fetch_http_events)

@data_bp.route('/dns_events', methods=['GET'])
def get_dns_events():
    return handle_request(data_service.fetch_dns_events)

@data_bp.route('/tetragon_logs', methods=['GET'])
def get_tetragon_logs():
    return handle_request(data_service.fetch_tetragon_logs)

@data_bp.route('/http_stix', methods=['GET'])
def get_http_stix():
    return handle_request(data_service.fetch_http_stix)

@data_bp.route('/dns_stix', methods=['GET'])
def get_dns_stix():
    return handle_request(data_service.fetch_dns_stix)

@data_bp.route('/tetragon_stix', methods=['GET'])
def get_tetragon_stix():
    return handle_request(data_service.fetch_tetragon_stix)

@data_bp.route('/kubescape_logs', methods=['GET'])
def get_kubescape_logs():
    return handle_request(data_service.fetch_kubescape_logs)

@data_bp.route('/kubescape_stix', methods=['GET'])
def get_kubescape_stix():
    return handle_request(data_service.fetch_kubescape_stix)