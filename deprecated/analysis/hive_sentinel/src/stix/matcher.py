from stix2matcher.matcher import match
from src.stix.attack_patterns import attack_patterns

STIX_VERSION = "2.1"

def get_pattern(STIX_ATTACK_PATTERN):
    for obj in STIX_ATTACK_PATTERN["objects"]:
        if obj["type"] == "indicator":
            return obj["pattern"], obj["id"]
    return None, None

def matches(pattern, bundle, stix_version=STIX_VERSION):
    try:
        return len(match(pattern, [bundle], stix_version=stix_version)) == 1
    except Exception as e:
        print(f"Error matching pattern {pattern} to bundle {bundle}: {e}")
        raise

def get_attack_patterns():
  return attack_patterns
