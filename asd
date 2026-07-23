sum(rate(node_cpu_seconds_total{mode!="idle"}[5m]) * on(node) group_left() (kube_node_role{role="physical-worker"} == 1))
