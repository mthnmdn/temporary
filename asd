- name: Get Tokens
  hosts: master[0]
  no_log: "{{ hide_logs | default(true) | bool }}"
  become: true
  gather_facts: false
  tasks:
    - name: Generate Join Command
      ansible.builtin.command: "kubeadm token create --ttl 30m --print-join-command"
      register: join_command_output
      changed_when: false
      #when: false

    - name: "Add K8S Token and Hash to Dummy Host"
      ansible.builtin.add_host:
        name:   "K8S_TOKEN_HOLDER"
        join_command: "{{ join_command_output.stdout }}"
      changed_when: false
      #when: false

- name: Add new worker
  hosts: workers
  no_log: "{{ hide_logs | default(true) | bool }}"
  become: true
  gather_facts: false
  tasks:

    - name: Copy kubernetes.sh to workers
      ansible.builtin.copy:
        src: ./cluster-init/kubernetes-135.sh
        dest: /tmp/kubernetes-135.sh
        mode: '0755'
      #when: false

    - name: Fix CRLF
      ansible.builtin.command: "sed -i 's/\r$//' /tmp/kubernetes-135.sh"
      #when: false

    - name: Execute kubernetes.sh
      ansible.builtin.command: /tmp/kubernetes-135.sh
      #when: false

    - name: Add new worker
      ansible.builtin.command: |
        {{ hostvars['K8S_TOKEN_HOLDER']['join_command'] }} --node-name {{ inventory_hostname }}
      args:
        creates: /etc/kubernetes/kubelet.conf
      #when: false

    - name: Set kubelet conf
      # Her host, ait olduğu alt grubun (physical/virtual) kubelet_config_source
      # değerini otomatik alır. Tanımlı değilse default_kubelet_config_source kullanılır.
      ansible.builtin.copy:
        src: "{{ kubelet_config_source }}"
        dest: /var/lib/kubelet/config.yaml
        owner: root
        group: root
        mode: '0640'
      notify: Restart kubelet
      #when: false

  handlers:
    - name: Restart kubelet
      ansible.builtin.systemd:
        name: kubelet
        state: restarted
        daemon_reload: true

- name: Label and Taint New Workers
  hosts: master[0]
  no_log: "{{ hide_logs | default(true) | bool }}"
  become: true
  gather_facts: false
  vars:
    kubeconfig: "/etc/kubernetes/admin.conf"
    # Her worker'da ortak olan label(lar)
    common_worker_labels: "node.kubernetes.io/exclude-from-external-load-balancers="
    default_worker_taints: "new-node=true:NoSchedule"
  tasks:

    - name: Add label to worker
      #when: false
      # worker'ın rol label'ı (physical/virtual) hostvars üzerinden alınır,
      # ortak label ile birleştirilerek uygulanır.
      ansible.builtin.command: |
        kubectl label no {{ worker }} {{ common_worker_labels }} {{ hostvars[worker]['worker_role_label'] }} --kubeconfig {{ kubeconfig }}
      loop: "{{ groups['workers'] | default([]) }}"
      loop_control:
        loop_var: worker

    - name: Add taint to worker
      #when: false
      ansible.builtin.command: |
        kubectl taint no {{ worker }} {{ default_worker_taints }} --kubeconfig {{ kubeconfig }}
      loop: "{{ groups['workers'] | default([]) }}"
      loop_control:
        loop_var: worker
