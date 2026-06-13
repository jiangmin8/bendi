# Odysseus MCP Tool Registry

## Table of Contents
1. [High-Risk Tools (Admin Only)](#high-risk-tools)
2. [Medium-Risk Tools](#medium-risk-tools)
3. [Low-Risk Tools (General Access)](#low-risk-tools)
4. [Tool Permission Matrix](#permission-matrix)

## High-Risk Tools

### shell_exec
- **Permission**: admin-only
- **Schema**: `{command: string, timeout?: number, cwd?: string}`
- **Risk**: Full system access, arbitrary code execution
- **Sandbox**: Runs in subprocess with timeout, no network isolation by default
- **Audit Point**: Check command injection via LLM-generated args

### file_read / file_write / file_delete
- **Permission**: admin-only
- **Schema**: `{path: string, content?: string}`
- **Risk**: Arbitrary filesystem access
- **Sandbox**: Path traversal checks needed
- **Audit Point**: Verify path sanitization prevents `../../../etc/passwd`

### email_send
- **Permission**: admin-only (requires IMAP/SMTP config)
- **Schema**: `{to: string[], subject: string, body: string}`
- **Risk**: Email spoofing, phishing via compromised agent

## Medium-Risk Tools

### web_search
- **Permission**: authenticated users
- **Schema**: `{query: string, num_results?: number}`
- **Risk**: SSRF if URL validation missing, data exfiltration

### calendar_query / calendar_create
- **Permission**: authenticated users (requires CalDAV)
- **Schema**: `{start_date: string, end_date?: string}` / `{title: string, start: string, end: string}`

## Low-Risk Tools

### memory_search / memory_store
- **Permission**: all authenticated users
- **Schema**: `{query: string, top_k?: number}` / `{key: string, value: string}`
- **Backend**: ChromaDB vector store

### model_compare
- **Permission**: all users
- **Schema**: `{prompt: string, models: string[]}`
- **Purpose**: Blind test multiple LLMs on same prompt

## Permission Matrix

| Tool | Guest | User | Admin |
|------|-------|------|-------|
| shell_exec | - | - | Y |
| file_read | - | - | Y |
| file_write | - | - | Y |
| email_send | - | - | Y |
| web_search | - | Y | Y |
| calendar_* | - | Y | Y |
| memory_* | - | Y | Y |
| model_compare | Y | Y | Y |
