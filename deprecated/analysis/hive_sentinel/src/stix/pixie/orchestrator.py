from src.stix.core import sanitize_bundle, generate_stix_id
from src.stix.pixie.transform_dns_to_stix import transform_dns_row_to_stix
from src.stix.pixie.transform_http_to_stix import transform_http_row_to_stix

def transform_pixie_log_to_stix(pixie_log, log_type):
    stix_object = {}
    if log_type == "dns_stix":
        stix_object = transform_dns_row_to_stix(pixie_log)
    elif log_type == "http_stix":
        stix_object = transform_http_row_to_stix(pixie_log)

    stix_bundle = {
        "type": "bundle",
        "id": generate_stix_id("bundle"),
        "spec_version": "2.1",
        "objects": stix_object,
    }

    return stix_object, stix_bundle
