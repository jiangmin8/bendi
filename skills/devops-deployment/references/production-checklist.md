# Production Readiness Checklist

## Pre-Launch

### Infrastructure
- [ ] Dedicated server (not shared with other services)
- [ ] Firewall configured (only 443 and SSH open)
- [ ] Automatic security updates enabled
- [ ] Docker daemon secured (TLS or socket protection)
- [ ] Container images pinned to specific digests (not `latest`)

### SSL/TLS
- [ ] Valid certificate (Let's Encrypt or purchased)
- [ ] HTTPS redirect from HTTP
- [ ] HSTS headers enabled
- [ ] Certificate auto-renewal configured

### Application
- [ ] `AUTH_ENABLED=true` (never skip)
- [ ] Strong admin password set
- [ ] API keys in `.env` (not in repo, not in logs)
- [ ] Debug mode disabled
- [ ] Health check endpoint responding
- [ ] Graceful shutdown handling (`SIGTERM`)

### Data
- [ ] Named volumes for persistent data
- [ ] Automated daily backups (off-site)
- [ ] Backup restore tested monthly
- [ ] Log rotation configured (no infinite growth)

## Post-Launch

### Monitoring
- [ ] Container health checks
- [ ] Disk usage alerts (<80%)
- [ ] Memory usage alerts
- [ ] SSL certificate expiry alert (30 days)
- [ ] Uptime monitoring (UptimeRobot/Pingdom)

### Security
- [ ] Fail2ban on SSH and app login
- [ ] Docker socket not exposed
- [ ] No containers running as root where avoidable
- [ ] Image vulnerability scan monthly
- [ ] Dependency audit monthly

### Scaling (if needed)
- [ ] Load balancer in front (for multi-instance)
- [ ] Shared storage for multi-node setups
- [ ] Session affinity if using WebSockets
