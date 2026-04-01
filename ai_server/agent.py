import yaml

CONFIG_PATH = "../configs/prompts.yaml"

def update_policy(new_watch_for):

    with open(CONFIG_PATH) as f:
        config = yaml.safe_load(f)

    config["watch_for"] = new_watch_for

    with open(CONFIG_PATH, "w") as f:
        yaml.dump(config, f)

    print("Policy updated:", new_watch_for)
