from pathlib import Path

from policy import PolicyEngine


PROMPT_FILE = Path(__file__).resolve().parent.parent / "configs" / "prompts.yaml"


def load_prompt() -> str:
    policy = PolicyEngine(PROMPT_FILE).get_policy()
    objects = policy.get("watch_for", [])
    return " . ".join(objects) if objects else "person . bag . bottle"
