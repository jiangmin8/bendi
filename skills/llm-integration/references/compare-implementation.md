# Compare Feature Architecture

## Flow

1. User enters prompt and selects models (2-4)
2. Backend fires parallel async requests:
```python
responses = await asyncio.gather(
    model_router.stream(prompt, model="gpt-4"),
    model_router.stream(prompt, model="claude-3"),
    model_router.stream(prompt, model="deepseek-v3"),
    return_exceptions=True
)
```
3. Each response gets anonymized ID (Model A, B, C)
4. Frontend displays side-by-side with live streaming
5. User votes for best response
6. Reveal shows which model was which

## Anonymization

```python
# Map real model IDs to anonymous labels
model_aliases = {}
for i, model_id in enumerate(selected_models):
    model_aliases[f"Model {chr(65+i)}"] = model_id  # A, B, C...

# Frontend never sees real model_id until reveal
```

## Aggregation Metrics

Track over time:
- Win rate per model
- Response latency per model
- Token count per model
- User preference trends

## Anti-Cheating

- Randomize order each comparison
- Don't reveal in progress (prevents waiting for "known fast" model)
- Include same model twice occasionally (consistency check)
