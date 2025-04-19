# Installs Consul Cluster using Hashi Vault as CA

<br>

## Vault Certificate Template Setup
```bash
vault write pki_int/roles/consul-cert \
  allowed_domains="corp.mycompany.com" \
  allow_subdomains=true \
  allow_bare_domains=true \
  enforce_hostnames=true \
  server_flag=true \
  client_flag=true \
  max_ttl="720h"
```
> this assumes DNS setup as below, with consul nodes having configured the arpa.local dns root dns servers as their preferred dns servers.
<br>

## DNS Setup

[ DNS Server (Primary for arpa.local) ]
                   |
    Delegation for arpa.local
                   ↓
      [ Consul Agent DNS on each node (UDP/TCP 8600) ]
                   ↓
       Consul DNS service registry & discovery

<br>
<br>

## Reference Architecture Considerations

https://developer.hashicorp.com/consul/tutorials/production-vms/reference-architecture

###

<br>

### Sizing
Size	CPU	        Memory	     Disk Capacity	Disk IO	    Disk Throughput
Small	2-4 core	8-16 GB RAM	 100+ GB	    3000+ IOPS	75+ MB/s
Large	8-16 core	32-64 GB RAM 200+ GB	    7500+ IOPS	250+

<br>

### Network latency and bandwidth
For data sent between all Consul agents the following latency requirements must be met:

    Average RTT for all traffic cannot exceed 50ms.
    RTT for 99 percent of traffic cannot exceed 100ms.

### Network policy recommendation
Guidance for Network Policy Configuration

When deploying Consul on Kubernetes with the AWS VPC CNI (or any other CNI), ensure you explicitly allow:

    Inbound and outbound for ports 8300, 8301, 8302 among Consul servers and clients in the same datacenter.
    Proper port ranges for sidecar proxies if Consul service mesh is enabled.
    Minimal latency between nodes to meet the gossip protocol’s requirements.

Checklist:

    Security Groups and Firewalls: Confirm rules for 8300 (TCP), 8301 (TCP & UDP), 8302 (TCP & UDP).
    Kubernetes NetworkPolicy: If using NetworkPolicy objects, verify all needed ports are explicitly allowed.
    Load Balancers or NAT Gateways: Check if your traffic paths require additional rules or NAT exceptions.
    High Availability: Validate multi-AZ deployments for latency with the constraints: Average RTT < 50 ms, 99% RTT < 100 ms.

Networking Best Practices

    Maintain Low Latency: Keep RTT below 50 ms average for all nodes in a datacenter to ensure stable gossip.
    Open Required Ports: 8300 (RPC), 8301 (LAN gossip), 8302 (WAN gossip), plus 8500 (HTTP), 8501 (HTTPS) and 8600 (DNS). Both inbound and outbound rules must allow these ports.
    Check Connectivity Regularly: Use scripts or Consul CLI command consul troubleshoot ports to verify that there are no blocked ports.
    Monitor Logs and Alerts: Set up alerts for connection failures, timeouts, or DENY messages in flow logs.
    Iterate on Logging: When you find connectivity failures, log details such as IP, port, and error type to speed up diagnosis.
