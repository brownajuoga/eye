import yaml

CONFIG_PATH = "../configs/prompts.yaml"


def load_policy():
    with open(CONFIG_PATH) as f:
        return yaml.safe_load(f)


def analyze_event(detections):

    config = load_policy()

    watch_for = set(config.get("watch_for", []))
    ignore = set(config.get("ignore", []))
    rules = config.get("rules", {})

    labels = [d["label"] for d in detections]

    event = {
        "important": False,
        "reason": "",
        "objects": labels
    }

    # Apply ignore filter
    filtered_labels = [l for l in labels if l not in ignore]

    # Rule: require person
    if rules.get("require_person", False):
        if "person" not in filtered_labels:
            event["reason"] = "No person detected"
            return event

    # Rule: watch_for objects
    for obj in watch_for:
        if obj in filtered_labels:
            event["important"] = True
            event["reason"] = f"Matched: {obj}"
            return event

    event["reason"] = "No important objects detected"
    return event
