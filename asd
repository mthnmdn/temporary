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

    - name: Store join command as a fact on master
      ansible.builtin.set_fact:
        join_command: "{{ join_command_output.stdout }}"
      #when: false

- name: Add new worker
  hosts: workers
  no_log: "{{ hide_logs | default(true) | bool }}"
  become: true
  gather_facts: false
  vars:
    # Gruba göre kubelet config kaynakları (sabit değerler, değişkene bağlı)
    physical_kubelet_config_source: "./physical-worker-kubelet-config.yaml"
    virtual_kubelet_config_source: "./virtual-worker-kubelet-config.yaml"
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
      # Join komutu master host'unun fact'inden okunuyor.
      ansible.builtin.command: |
        {{ hostvars[groups['master'][0]]['join_command'] }} --node-name {{ inventory_hostname }}
      args:
        creates: /etc/kubernetes/kubelet.conf
      #when: false

    - name: Set kubelet conf
      # Host physical-workers grubundaysa physical config, değilse virtual config kullanılır.
      ansible.builtin.copy:
        src: "{{ physical_kubelet_config_source if inventory_hostname in (groups['physical-workers'] | default([])) else virtual_kubelet_config_source }}"
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
    # Sabit label'lar, değişkene bağlı
    physical_worker_labels: "node.kubernetes.io/exclude-from-external-load-balancers= node-role.kubernetes.io/physical-worker="
    virtual_worker_labels: "node.kubernetes.io/exclude-from-external-load-balancers= node-role.kubernetes.io/virtual-worker="
    default_worker_taints: "new-node=true:NoSchedule"
  tasks:

    - name: Label physical workers
      #when: false
      ansible.builtin.command: |
        kubectl label no {{ worker }} {{ physical_worker_labels }} --kubeconfig {{ kubeconfig }}
      loop: "{{ groups['physical-workers'] | default([]) }}"
      loop_control:
        loop_var: worker

    - name: Label virtual workers
      #when: false
      ansible.builtin.command: |
        kubectl label no {{ worker }} {{ virtual_worker_labels }} --kubeconfig {{ kubeconfig }}
      loop: "{{ groups['virtual-workers'] | default([]) }}"
      loop_control:
        loop_var: worker

    - name: Add taint to worker
      #when: false
      ansible.builtin.command: |
        kubectl taint no {{ worker }} {{ default_worker_taints }} --kubeconfig {{ kubeconfig }}
      loop: "{{ groups['workers'] | default([]) }}"
      loop_control:
        loop_var: worker
