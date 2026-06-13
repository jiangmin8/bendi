# Memory Lifecycle

## Data Flow

```
User Input
  -> Agent processes
    -> Important info extracted
      -> Chunked (if long)
        -> Embedded
          -> Stored in ChromaDB (per-user collection)
            -> Retrieved on next relevant query
```

## Storage Triggers

| Event | What Gets Stored |
|-------|-----------------|
| Chat response | Conversation turn (summary or full) |
| Tool execution | Tool input + output |
| Web search | Search query + top results |
| User preference | Explicit settings/preferences |
| Calendar event | Event details + context |

## Retrieval Flow

```python
async def augment_with_memory(query: str, user_id: str):
    collection = get_user_collection(user_id)
    
    # Semantic search
    results = collection.query(
        query_texts=[query],
        n_results=5,
        where={"timestamp": {"$gt": one_week_ago}}  # recency filter
    )
    
    # Format for prompt
    context = "\n\n".join(
        f"[Memory {i+1}]: {doc}"
        for i, doc in enumerate(results["documents"][0])
    )
    
    return f"Relevant context:\n{context}\n\nUser query: {query}"
```

## Eviction Strategies

| Strategy | When | Risk |
|----------|------|------|
| **Time-based** | Delete older than N days | Lose long-term knowledge |
| **Count-based** | Keep top N per collection | Lose infrequent topics |
| **Importance** | LLM scores importance, evict low | Scoring overhead |
| **None** | Keep everything | Storage growth, slower search |

## Cross-Session Leakage Prevention

- Always use per-user collections: `collection_name = f"user_{user_id}"`
- Never share collection between users
- Include `user_id` in all collection operations
- Validate user ownership before query/delete
