FROM ubuntu:24.04

RUN apt-get update && apt-get install -y curl jq && rm -rf /var/lib/apt/lists/*

# Start: exact documented docker run command
RUN printf '#!/usr/bin/env bash\n\
if distrobox-host-exec podman ps -a --format "{{.Names}}" | grep -q "^crawl4ai$"; then\n\
  echo "crawl4ai already exists. Run: crawl4ai-stop first." >&2; exit 1\n\
fi\n\
distrobox-host-exec podman run -d \\\n\
  --name crawl4ai \\\n\
  -p 11235:11235 \\\n\
  --shm-size=1g \\\n\
  unclecode/crawl4ai:latest\n\
echo "Crawl4AI started"\n\
echo "  Playground: http://localhost:11235/playground"\n\
echo "  Dashboard:  http://localhost:11235/monitor"\n\
echo "  MCP SSE:    http://localhost:11235/mcp/sse"\n\
' > /usr/bin/crawl4ai-start && chmod +x /usr/bin/crawl4ai-start

# Stop
RUN printf '#!/usr/bin/env bash\n\
distrobox-host-exec podman stop crawl4ai\n\
distrobox-host-exec podman rm crawl4ai\n\
' > /usr/bin/crawl4ai-stop && chmod +x /usr/bin/crawl4ai-stop

# Status: container state + API health
RUN printf '#!/usr/bin/env bash\n\
distrobox-host-exec podman ps -a -f name=crawl4ai \\\n\
  --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"\n\
curl -sf http://localhost:11235/health | jq . || echo "(API not reachable)"\n\
' > /usr/bin/crawl4ai-status && chmod +x /usr/bin/crawl4ai-status

CMD ["/bin/bash"]
