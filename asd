sum(rate(node_cpu_seconds_total{mode!="idle"}[5m]) * on(instance) group_left() label_replace(kube_node_role{role="physical-worker"}, "instance", "$1", "node", "(.*)"))
