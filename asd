---
# Cluster inventory validation playbook
# Call this first (e.g. via import_playbook). Any failed check stops the whole
# run immediately thanks to `any_errors_fatal: true`.
#
# Play 1 - structural / variable checks, run locally against the inventory.
# Play 2 - remote checks on worker nodes (must be clean of any prior install).

- name: Validate inventory structure and variables
  hosts: localhost
  connection: local
  gather_facts: false
  any_errors_fatal: true

  vars:
    # Leaf role groups (parent group 'workers' and 'all' are intentionally excluded).
    # All overlap/orphan checks are derived from this list - adding a new role
    # group (e.g. gpu-workers) here is enough to include it in the checks.
    leaf_groups:
      - master
      - physical-workers
      - virtual-workers
    # Groups that must exist in the inventory (leaf groups + parent group)
    required_groups: "{{ leaf_groups + ['workers'] }}"
    allowed_k8s_versions:
      - "1.35"
      - "1.33"
    # Hosts whose name does not start with lks/lk8s
    invalid_named_hosts: "{{ groups['all'] | reject('match', '^(lks|lk8s)') | list }}"
    # Union of the two worker leaf groups (union = concatenate + deduplicate)
    worker_union: "{{ groups['physical-workers'] | union(groups['virtual-workers']) }}"
    # Every host that appears in at least one leaf role group
    role_assigned_hosts: "{{ leaf_groups | map('extract', groups) | flatten | unique }}"
    # Hosts that are in the inventory but not in any leaf role group
    orphan_hosts: "{{ groups['all'] | difference(role_assigned_hosts) }}"

  tasks:

    # ---- Requirement 0: all expected groups must exist in the inventory ----
    # Runs first: a typo in a group name would otherwise let every other
    # check pass silently against an empty default list.
    - name: Ensure all required groups exist in the inventory
      ansible.builtin.assert:
        that:
          - required_groups | difference(groups.keys()) | length == 0
        fail_msg: >-
          Missing groups in inventory:
          {{ required_groups | difference(groups.keys()) }}
        success_msg: "All required groups exist"
        quiet: true

    # ---- Requirement 1: each host belongs to only one leaf role group ----
    # Pairwise intersection of every leaf group combination, generated
    # dynamically from leaf_groups.
    - name: Ensure no host belongs to more than one role group
      ansible.builtin.assert:
        that:
          - groups[item.0] | intersect(groups[item.1]) | length == 0
        fail_msg: >-
          Hosts present in both '{{ item.0 }}' and '{{ item.1 }}':
          {{ groups[item.0] | intersect(groups[item.1]) }}
        success_msg: "No overlap between '{{ item.0 }}' and '{{ item.1 }}'"
        quiet: true
      loop: "{{ leaf_groups | product(leaf_groups) | list }}"
      when: item.0 < item.1  # each unordered pair once, no self-comparison

    # ---- Extra: no orphan hosts (every host must be in exactly one role group) ----
    - name: Ensure there are no orphan hosts (host in inventory but no role group)
      ansible.builtin.assert:
        that:
          - orphan_hosts | length == 0
        fail_msg: "These hosts are not assigned to any role group: {{ orphan_hosts }}"
        success_msg: "Every host is assigned to a role group"
        quiet: true

    # ---- Extra: master group must not be empty ----
    - name: Ensure the master group has at least one host
      ansible.builtin.assert:
        that:
          - groups['master'] | length >= 1
        fail_msg: "The 'master' group is empty - at least one control-plane node is required"
        success_msg: "master group is populated"
        quiet: true

    # ---- Requirement 2: at least one worker group must be non-empty ----
    - name: Ensure physical and virtual worker groups are not both empty
      ansible.builtin.assert:
        that:
          - worker_union | length > 0
        fail_msg: "Both physical-workers and virtual-workers are empty - at least one must have a host"
        success_msg: "At least one worker group is populated"
        quiet: true

    # ---- Requirement 3: kubernetes_version must be an allowed value ----
    - name: Ensure kubernetes_version is one of the allowed values
      ansible.builtin.assert:
        that:
          - kubernetes_version is defined
          - (kubernetes_version | string | trim) in allowed_k8s_versions
        fail_msg: >-
          kubernetes_version must be one of {{ allowed_k8s_versions }}
          (current: '{{ kubernetes_version | default("undefined") | string | trim }}')
        success_msg: "kubernetes_version is valid"
        quiet: true

    # ---- Requirement 4: all host names must start with lks or lk8s ----
    - name: Ensure all host names start with 'lks' or 'lk8s'
      ansible.builtin.assert:
        that:
          - invalid_named_hosts | length == 0
        fail_msg: "These host names do not start with 'lks' or 'lk8s': {{ invalid_named_hosts }}"
        success_msg: "All host names follow the naming convention"
        quiet: true

    # ---- Requirement 5: workers children must be exactly physical + virtual ----
    - name: Ensure workers group equals the union of physical and virtual workers
      ansible.builtin.assert:
        that:
          - (groups['workers'] | sort) == (worker_union | sort)
        fail_msg: >-
          workers group membership does not match physical-workers ∪ virtual-workers.
          workers={{ groups['workers'] | sort }},
          expected={{ worker_union | sort }}
        success_msg: "workers group matches its expected children"
        quiet: true

- name: Validate that worker nodes are clean (no prior kubeadm install)
  hosts: workers
  gather_facts: false
  any_errors_fatal: true

  vars:
    # Ports that must be free on a worker before kubeadm join
    required_free_ports:
      - 10250   # kubelet API
      - 10256   # kube-proxy health check

  tasks:

    # ---- Extra: connectivity pre-check for a clear error if a node is unreachable ----
    - name: Verify the node is reachable
      ansible.builtin.ping:

    # ---- Requirement 6a: /etc/kubernetes/kubelet.conf must not exist ----
    - name: Check for kubelet.conf
      ansible.builtin.stat:
        path: /etc/kubernetes/kubelet.conf
      register: kubelet_conf

    # ---- Requirement 6b: no cilium CNI config under /etc/cni/net.d ----
    - name: Look for cilium CNI config under /etc/cni/net.d
      ansible.builtin.find:
        paths: /etc/cni/net.d
        patterns: "*cilium*"
        file_type: any
      register: cilium_cni

    - name: Ensure no prior kubeadm installation (kubelet.conf absent)
      ansible.builtin.assert:
        that:
          - not kubelet_conf.stat.exists
        fail_msg: "{{ inventory_hostname }}: prior kubeadm install detected - /etc/kubernetes/kubelet.conf exists"
        success_msg: "{{ inventory_hostname }}: no kubelet.conf found"
        quiet: true

    - name: Ensure no cilium CNI component is present
      ansible.builtin.assert:
        that:
          - cilium_cni.matched == 0
        fail_msg: >-
          {{ inventory_hostname }}: cilium CNI config found under /etc/cni/net.d →
          {{ cilium_cni.files | map(attribute='path') | list }}
        success_msg: "{{ inventory_hostname }}: no cilium CNI config found"
        quiet: true

    # ---- Extra: kubelet service must not be running ----
    # The kubelet service may be installed (kubelet package present) - that is
    # fine. What matters is that it is not running: 'kubeadm reset' stops
    # kubelet but does not disable it, so after a reboot it may come back.
    - name: Gather service facts
      ansible.builtin.service_facts:

    - name: Ensure the kubelet service is not running (installed is fine)
      ansible.builtin.assert:
        that:
          - ansible_facts.services['kubelet.service'].state | default('stopped') != 'running'
        fail_msg: >-
          {{ inventory_hostname }}: kubelet service is running - stop it before
          installation (systemctl stop kubelet)
        success_msg: "{{ inventory_hostname }}: kubelet service is not running"
        quiet: true

    # ---- Extra: kubernetes ports must not be in use ----
    # wait_for with state=stopped returns immediately if nothing listens on
    # the port, and fails after the timeout if something does.
    - name: Ensure required kubernetes ports are free
      ansible.builtin.wait_for:
        port: "{{ item }}"
        state: stopped
        timeout: 3
        msg: "{{ inventory_hostname }}: port {{ item }} is already in use - a kubelet/kube-proxy may still be running"
      loop: "{{ required_free_ports }}"
