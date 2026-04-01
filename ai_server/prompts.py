import yaml

PROMPT_FILE = "../configs/prompts.yaml"

def load_prompt():
    try:
        with open(PROMPT_FILE) as f:
            data = yaml.safe_load(f)
        objects = data.get("watch_for", [])
        return " . ".join(objects)
    except Exception:
        return "person . dog . chair"
