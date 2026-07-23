#---- fiziksel worker'ların total cpu kullanımı ----
sum(rate(node_cpu_seconds_total{mode!="idle"}[5m]) * on(instance) group_left() label_replace(kube_node_role{role="physical-worker"}, "instance", "$1", "node", "(.*)"))

#---- fiziksel worker'ların ortalama cpu request oranı ----
100 * sum(kube_pod_container_resource_requests{resource="cpu"} * on(pod, namespace) group_left() (kube_pod_status_phase{phase="Running"} == 1) * on(node) group_left() (kube_node_role{role="physical-worker"} == 1)) / sum(kube_node_status_allocatable{resource="cpu"} * on(node) group_left() (kube_node_role{role="physical-worker"} == 1))

#---- fiziksel worker'ların total memory kullanımı ----
sum((node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) * on(instance) group_left() label_replace(kube_node_role{role="physical-worker"}, "instance", "$1", "node", "(.*)")) / 1024 / 1024 / 1024

#---- fiziksel worker'ların ortalama memory request oranı ----
100 * sum(kube_pod_container_resource_requests{resource="memory"} * on(pod, namespace) group_left() (kube_pod_status_phase{phase="Running"} == 1) * on(node) group_left() (kube_node_role{role="physical-worker"} == 1)) / sum(kube_node_status_allocatable{resource="memory"} * on(node) group_left() (kube_node_role{role="physical-worker"} == 1))
