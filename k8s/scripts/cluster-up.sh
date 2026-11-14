#!/bin/sh
# Creates (or resumes) a dedicated Colima VM with k3s. The default Colima profile, which runs the
# Compose stack and holds its volumes, is never started, stopped or modified by this script.
. "$(dirname "$0")/env.sh"
CPUS="${CPUS:-6}"
MEMORY_GIB="${MEMORY_GIB:-6}"
previous_docker_context="$(docker context show)"
colima start --profile "$COLIMA_PROFILE" --vm-type vz --cpu "$CPUS" --memory "$MEMORY_GIB" --disk 60 --kubernetes
# colima switches the global Docker context to the new profile; restore the previous one.
docker context use "$previous_docker_context" >/dev/null

# k3s pins the node IP it saw when the VM was created. Both Colima VMs share one network, and the
# address each gets depends on which boots first, so after a restart the pin can name the other VM:
# pods then cannot reach the API server, CoreDNS never becomes ready, and every init container waits
# forever (seen 14 Nov 2026). Re-pin to this boot's address and restart k3s; data and pods are kept.
colima ssh --profile "$COLIMA_PROFILE" -- sh -c '
  ip=$(ip -4 -o addr show eth0 | awk "{print \$4}" | cut -d/ -f1)
  pinned=$(sed -n "s/^node-ip: //p" /etc/rancher/k3s/config.yaml)
  if [ -n "$ip" ] && [ "$ip" != "$pinned" ]; then
    echo "k3s node-ip was $pinned, this boot is $ip: re-pinning and restarting k3s"
    sudo sed -i "s/^node-ip: .*/node-ip: $ip/" /etc/rancher/k3s/config.yaml
    sudo systemctl restart k3s
  fi'

kubectl --context "$KUBE_CONTEXT" wait --for=condition=Ready node --all --timeout=180s
kubectl --context "$KUBE_CONTEXT" -n kube-system wait --for=condition=Ready pod -l k8s-app=kube-dns --timeout=180s
kubectl --context "$KUBE_CONTEXT" get nodes -o wide
