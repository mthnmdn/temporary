- name: Ensure required inventory variables are defined and not empty
      ansible.builtin.assert:
        that:
          - vars[item] is defined
          - vars[item] | string | trim | length > 0
        fail_msg: "{{ inventory_hostname }}: '{{ item }}' is not defined or is empty in the inventory"
        success_msg: "{{ inventory_hostname }}: '{{ item }}' is defined"
        quiet: true
      loop:
        - cluster_name
        - api_address
        - company_name
        - business
        - domain
        - env
        - platform
        - pfx_pass
        - pfx
        - username
        - cluster_env
      loop_control:
        label: "{{ item }}"

    - name: Check kubelet.conf
      ansible.builtin.stat:
        path: /etc/kubernetes/kubelet.conf
      register: kubelet_conf

    - name: Check config.toml
      ansible.builtin.stat:
        path: /etc/containerd/config.toml
      register: containerd_conf

    - name: Check kube-apiserver manifest
      ansible.builtin.stat:
        path: /etc/kubernetes/manifests/kube-apiserver.yaml
      register: apiserver_manifest

    - name: Ensure node is clean (proceed only if none of the 3 files exist)
      ansible.builtin.assert:
        that:
          - not kubelet_conf.stat.exists
          - not containerd_conf.stat.exists
          - not apiserver_manifest.stat.exists
        fail_msg: >-
          {{ inventory_hostname }}: node is not clean, leftovers from a previous installation found →
          kubelet.conf={{ kubelet_conf.stat.exists }},
          config.toml={{ containerd_conf.stat.exists }},
          apiserver_manifest={{ apiserver_manifest.stat.exists }}
        success_msg: "{{ inventory_hostname }}: node is clean, safe to proceed"
        quiet: true
