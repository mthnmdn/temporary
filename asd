sum(
  rate(node_cpu_seconds_total{mode!="idle"}[5m])
  * on(instance) group_left()
  (kube_node_labels{label_physical_worker="true"} 
   * on(node) group_left(instance) 
   label_replace(kube_node_info, "instance", "$1", "node", "(.*)"))
)
