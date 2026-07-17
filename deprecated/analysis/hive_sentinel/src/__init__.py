from flask import Flask
from src.routes import register_routes
from src.etl.stix_etl.controller import start_stix_etls
import sys
IS_PYTEST = "pytest" in sys.modules

def create_app():
    app = Flask(__name__)
    register_routes(app)

    if not IS_PYTEST:
      start_stix_etls()

    return app
