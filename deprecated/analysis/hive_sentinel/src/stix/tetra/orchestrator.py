import json
from src.stix.core import generate_stix_id, sanitize_bundle, create_relationship
from src.stix.matcher import get_attack_patterns, get_pattern, matches
from src.stix.tetra.transformer import transform_kprobe_to_stix

def transform_tetragon_to_stix(tetragon_logs):
    stix_bundles = []
    all_stix_objects = []
    STIX_ATTACK_PATTERNS = get_attack_patterns()

    for log in tetragon_logs:
        stix_objects = []

        if "process_exec" in log:
            stix_objects.extend(transform_kprobe_to_stix(log["process_exec"], log.get("node_name"), {}))
        elif "process_kprobe" in log:
            stix_objects.extend(transform_kprobe_to_stix(log["process_kprobe"], log.get("node_name"), log))

        output_to_save = json.dumps(sanitize_bundle(stix_objects))
        all_stix_objects.extend(stix_objects)

        matching_patterns = []
        for STIX_ATTACK_PATTERN in STIX_ATTACK_PATTERNS:
            pattern, indicator_id = get_pattern(STIX_ATTACK_PATTERN)
            pattern_id = STIX_ATTACK_PATTERN["id"]

            temp_bundle = {"objects": stix_objects}
            if matches(pattern, temp_bundle):
                matching_patterns.append((indicator_id, pattern_id, STIX_ATTACK_PATTERN))

        if matching_patterns:
            stix_bundle = {
                "type": "bundle",
                "id": generate_stix_id("bundle"),
                "spec_version": "2.1",
                "objects": stix_objects,
            }

            for indicator_id, pattern_id, STIX_ATTACK_PATTERN in matching_patterns:
                print(f"Matched pattern ID: {pattern_id}, Indicator ID: {indicator_id}")
                indicator_relationship = create_relationship(stix_bundle["id"], indicator_id, "indicates")
                stix_bundle["objects"].append(indicator_relationship)

                for obj in stix_bundle["objects"]:
                    if obj.get("type") == "observed-data":
                        obj["object_refs"].append(indicator_id)
                        break

            for _, _, STIX_ATTACK_PATTERN in matching_patterns:
                stix_bundle["objects"].extend(STIX_ATTACK_PATTERN["objects"])

            output_to_save = json.dumps(sanitize_bundle(stix_bundle))
            stix_bundles.append(stix_bundle)

    return all_stix_objects, stix_bundles
