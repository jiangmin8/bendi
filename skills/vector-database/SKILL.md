---
name: vector-database
description: Vector database integration for AI Agent memory systems. Use when analyzing embedding-based memory, RAG (Retrieval-Augmented Generation), ChromaDB configuration, vector search, similarity queries, and persistent conversation context in agent platforms like Odysseus. Covers embedding models, collection management, distance metrics, and memory lifecycle.
---

# Vector Database Analysis

Analyze embedding-based memory systems in AI Agents.

## Core Concepts

| Concept | Purpose |
|---------|---------|
| **Embeddings** | Text -> dense vector (768-1536 dimensions) |
| **Vector Store** | Persistent storage + similarity search |
| **RAG** | Retrieve relevant docs, augment LLM prompt |
| **Collection** | Isolated namespace (per-user or per-session) |
| **Distance Metric** | Cosine, Euclidean, dot product for similarity |

## Odysseus Memory Architecture

Uses ChromaDB for persistent cross-conversation memory:

- **Embedding Model**: Default `all-MiniLM-L6-v2` (local) or OpenAI embeddings
- **Collections**: One per user for isolation
- **Storage Types**: Conversations, tool results, web search results, user preferences
- **Retrieval**: Top-k similarity search with optional metadata filters

## Analysis Workflow

### When Analyzing Memory Implementation

1. Check embedding model (local vs API, dimension size)
2. Verify collection isolation (per-user or shared)
3. Review chunking strategy (document splitting)
4. Check metadata attached to vectors (timestamps, source, type)
5. Analyze retrieval: top_k value, distance metric, filters
6. Audit for data leakage between users/sessions
7. Check memory cleanup (old data eviction)

### When Analyzing RAG Pipeline

1. Trace ingestion: document -> chunks -> embeddings -> store
2. Trace retrieval: query -> embedding -> similarity search -> top_k results
3. Check context assembly: how retrieved chunks are injected into prompt
4. Measure retrieval quality (relevance of top results)

## Key Files

- `references/chromadb-setup.md` — ChromaDB configuration and API
- `references/memory-lifecycle.md` — Memory creation, retrieval, eviction flow
