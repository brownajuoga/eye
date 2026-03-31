IMPORTANT_OBJECTS = {
    "person",
    "backpack",
    "handbag",
    "cell phone",
    "bottle",
    "laptop"
}

def analyze_event(detections):

    labels = [d["label"] for d in detections]

    event = {
        "important": False,
        "reason": "",
        "objects": labels
    }

    # Rule 1: No person → ignore
    if "person" not in labels:
        event["reason"] = "No person detected"
        return event

    # Rule 2: Person + object of interest
    for obj in IMPORTANT_OBJECTS:
        if obj in labels:
            event["important"] = True
            event["reason"] = f"Person with {obj}"
            return event

    # Rule 3: Person only
    event["reason"] = "Person detected (no object)"
    return event
