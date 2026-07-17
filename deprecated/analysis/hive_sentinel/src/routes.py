from flask import Flask
from src.tetra_log.controller import tetra_bp
from src.stix.controller import stix_bp
from src.kubescape_log.controller import kubescape_bp
from src.severity_analysis.controller import analysis_bp
from src.etl.pixie_etl.controller import pixie_bp
from src.clickhouse_api.controller import data_bp
from src.etl.pattern_matcher.controller import pattern_bp


def register_routes(app: Flask):
    app.register_blueprint(tetra_bp)
    app.register_blueprint(stix_bp)
    app.register_blueprint(kubescape_bp)
    app.register_blueprint(analysis_bp)
    app.register_blueprint(pixie_bp)
    app.register_blueprint(data_bp)
    app.register_blueprint(pattern_bp)
