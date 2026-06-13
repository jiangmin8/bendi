---
name: security-audit
description: Security auditing for self-hosted AI Agent systems. Use when assessing authentication, authorization, sandbox isolation, prompt injection risks, tool permission escalation, data exfiltration vectors, and deployment security of MCP-based agents like Odysseus. Covers OWASP-style analysis for AI applications with shell access, file system tools, and external integrations.
---

# AI Agent Security Audit

Audit security posture of self-hosted AI Agent systems.

## Core Risk Model

Self-hosted agents with tool access create unique attack surface:

| Layer | Risk | Severity |
|-------|------|----------|
| **Network** | Exposed admin panel, no TLS, open ports | Critical |
| **Authentication** | Missing auth, weak passwords, session hijacking | Critical |
| **Authorization** | Tool permission escalation, role bypass | Critical |
| **Tool Sandbox** | Shell escape, path traversal, SSRF | Critical |
| **LLM Layer** | Prompt injection, tool description poisoning | High |
| **Data** | Memory leakage between users, logging of secrets | High |
| **Dependencies** | Vulnerable packages, supply chain | Medium |

## Odysseus-Specific Risk Areas

1. **Shell Execution Tool**: Arbitrary code execution if LLM is tricked
2. **File System Tools**: Path traversal to read sensitive files
3. **Email Integration**: Phishing/spam via compromised agent
4. **Web Search**: SSRF to internal services
5. **Persistent Memory**: Cross-user data leakage
6. **Multi-Model**: API key exposure in logs or memory

## Audit Workflow

1. **Authentication Check**: Verify `AUTH_ENABLED=true`, strong password policy
2. **Authorization Matrix**: Confirm tool permissions match user roles
3. **Sandbox Review**: Check subprocess isolation, timeout, resource limits
4. **Prompt Injection Test**: Attempt to bypass tool restrictions via crafted inputs
5. **Network Scan**: Verify no unnecessary ports exposed
6. **Secret Audit**: Check API keys not in logs, memory, or error messages
7. **Dependency Scan**: Run `pip audit` or `safety check`

## Key Files

- `references/security-checklist.md` — Complete audit checklist with commands
- `references/prompt-injection-patterns.md` — Known attack patterns and mitigations
