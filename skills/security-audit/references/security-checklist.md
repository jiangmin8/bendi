# Security Audit Checklist

## Pre-Deployment Checks

### Authentication
- [ ] `AUTH_ENABLED=true` is set (never run without auth)
- [ ] Strong password minimum requirements enforced
- [ ] JWT tokens use secure secret (not default/dev secret)
- [ ] Token expiration is configured (not infinite)
- [ ] Session invalidation on password change
- [ ] Rate limiting on login endpoints (fail2ban or in-app)

### Authorization
- [ ] Tool permissions match documented matrix
- [ ] Non-admin users cannot access `shell_exec`
- [ ] Role checks enforced server-side (not just UI hiding)
- [ ] API endpoints verify authentication on every request
- [ ] Admin endpoints have additional logging

### Network
- [ ] TLS/SSL enabled (HTTPS only, no HTTP fallback)
- [ ] No exposed database ports (ChromaDB not on public network)
- [ ] Firewall blocks all ports except 443 and SSH
- [ ] Internal services use Docker internal network

## Runtime Checks

### Tool Sandbox
- [ ] Shell commands run with timeout (default 30s)
- [ ] Subprocess env sanitized (no API keys inherited)
- [ ] File access restricted to allowed directories
- [ ] Path traversal protection on all file paths
- [ ] No `sudo` or setuid binaries accessible

### Data Protection
- [ ] API keys never logged to stdout/stderr
- [ ] Error messages don't expose internal paths or configs
- [ ] Memory (ChromaDB) uses isolated collections per user
- [ ] Chat history encrypted at rest if containing sensitive data
- [ ] Backup files have same permission as original data

### LLM Security
- [ ] Tool descriptions don't leak internal architecture
- [ ] System prompt resistant to injection (delimiter defense)
- [ ] User input sanitized before embedding in prompts
- [ ] Tool results don't auto-execute without LLM review
- [ ] Max token limits prevent resource exhaustion

## Post-Deployment Monitoring

- [ ] Failed auth attempts logged and alerted
- [ ] Tool execution logged with user attribution
- [ ] Unusual shell commands trigger alerts
- [ ] Disk usage monitored (prevent log filling disk)
- [ ] Dependency vulnerabilities scanned monthly

## Audit Commands

```bash
# Check for secrets in code
git log --all --full-history -- .env
grep -r "sk-" . --include="*.py" --include="*.js" 2>/dev/null

# Dependency vulnerabilities
pip install safety && safety check

# Container security scan
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image odysseus:latest

# Network exposure check
nmap -p 3000,8000,11434 <host>
```
