# eye UI

Minimal Flutter control surface for the `eye` surveillance system.

## Planned Screens

- Dashboard
- Model Manager
- Control Panel
- Event Logs
- Automation Rules

## Why This Structure

- Keeps UI concerns separate from Go scout and Python AI server
- Makes it easy to replace mock data with REST or websocket services later
- Supports desktop or web deployment from the same codebase

## Next Integration Steps

1. Add an API client for `/health`, `/state`, and `/analyze`
2. Add model upload and activation endpoints on the AI server
3. Replace mock data with polling or streaming state
4. Add authentication only if you expose the UI remotely
