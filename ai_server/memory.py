import time

memory_store = []

def store_event(event, detections, expert=None):

    entry = {
        "timestamp": time.time(),
        "event": event,
        "detections": detections,
        "expert": expert
    }

    memory_store.append(entry)

    # keep memory small (last 100 events)
    if len(memory_store) > 100:
        memory_store.pop(0)


def query_memory():

    return memory_store[-10:]  # last 10 events
