# ChromaDB Configuration

## Table of Contents
1. [Deployment Modes](#deployment-modes)
2. [Collection Management](#collection-management)
3. [Embedding Functions](#embedding-functions)
4. [Query API](#query-api)
5. [Performance Tuning](#performance-tuning)

## Deployment Modes

### Client-Server (Odysseus default)
```python
import chromadb
client = chromadb.HttpClient(host="chromadb", port=8000)
```

### Persistent Local
```python
client = chromadb.PersistentClient(path="./chroma_data")
```

### Ephemeral (testing)
```python
client = chromadb.EphemeralClient()
```

## Collection Management

```python
# Create collection with custom embedding
client.create_collection(
    name=f"user_{user_id}",  # per-user isolation
    embedding_function=embedding_fn,
    metadata={"hnsw:space": "cosine"}  # distance metric
)

# Add documents
collection.add(
    documents=["conversation content...", "tool result..."],
    metadatas=[{"type": "chat", "timestamp": "2026-01-01"}, 
               {"type": "tool", "tool": "web_search"}],
    ids=["conv_001", "tool_001"]
)

# Query
collection.query(
    query_texts=["user question"],
    n_results=5,
    where={"type": "chat"},  # metadata filter
    where_document={"$contains": "keyword"}  # content filter
)
```

## Embedding Functions

| Provider | Model | Dimensions | Local |
|----------|-------|-----------|-------|
| SentenceTransformers | `all-MiniLM-L6-v2` | 384 | Yes |
| SentenceTransformers | `all-mpnet-base-v2` | 768 | Yes |
| OpenAI | `text-embedding-3-small` | 1536 | No |
| OpenAI | `text-embedding-3-large` | 3072 | No |

## Distance Metrics

- `cosine`: Best for semantic similarity (default, recommended)
- `l2`: Euclidean distance
- `ip`: Inner product

## Performance Tuning

```python
# HNSW index parameters (in collection metadata)
{
    "hnsw:space": "cosine",
    "hnsw:construction_ef": 128,   # build accuracy
    "hnsw:search_ef": 64,          # query accuracy
    "hnsw:M": 16                   # connections per node
}
```

Larger `ef` = better accuracy, slower search.
