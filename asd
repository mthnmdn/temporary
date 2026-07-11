---
# Inventory validation playbook
# Usage: call this via `import_playbook` at the very top of your main play.
#   - import_playbook: validate_inventory.yml
# If any check fails, `any_errors_fatal: true` stops the entire run immediately,
# so no subsequent playbook will execute.

- name: Validate inventory and node prerequisites
  hosts: all:!hub
  gather_facts: false
  any_errors_fatal: true

  vars:
    required_vars:
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

    allowed_env:
      - test
      - prod
      - dmz

    allowed_cluster_env:
      - TEMP_PRODUCTION
      - TEMP_TEST
      - TEMP_DMZDMN

    # env -> cluster_env consistency mapping
    env_cluster_env_map:
      test: TEMP_TEST
      prod: TEMP_PRODUCTION
      dmz: TEMP_DMZDMN

    # api_address must look like: api.<cluster_name>.<something>.com:6443
    api_address_regex: "^api\\.{{ cluster_name | regex_escape }}\\.[a-zA-Z0-9-]+\\.com:6443$"

    # Expected pfx file name and its local path (under the playbook's files/ dir)
    expected_pfx_name: "ingress-{{ cluster_name }}.pfx"
    expected_pfx_path: "{{ playbook_dir }}/files/{{ expected_pfx_name }}"

  tasks:

    # ------------------------------------------------------------------
    # Global checks (inventory-wide) - run only once, not per host
    # ------------------------------------------------------------------

    - name: Ensure group sizes meet the minimum requirements
      ansible.builtin.assert:
        that:
          - groups['master'] | default([]) | length >= 3
          - groups['infra'] | default([]) | length >= 3
          - groups['hub'] | default([]) | length >= 1
        fail_msg: >-
          Group size requirement not met →
          master={{ groups['master'] | default([]) | length }} (min 3),
          infra={{ groups['infra'] | default([]) | length }} (min 3),
          hub={{ groups['hub'] | default([]) | length }} (min 1)
        success_msg: "Group sizes are valid"
        quiet: true
      run_once: true

    - name: Ensure master/infra/worker groups do not share any host
      # A host must belong to only one role group. Hub is intentionally excluded.
      ansible.builtin.assert:
        that:
          - groups['master'] | default([]) | intersect(groups['infra'] | default([])) | length == 0
          - groups['master'] | default([]) | intersect(groups['worker'] | default([])) | length == 0
          - groups['infra'] | default([]) | intersect(groups['worker'] | default([])) | length == 0
        fail_msg: >-
          A host appears in more than one role group →
          master∩infra={{ groups['master'] | default([]) | intersect(groups['infra'] | default([])) }},
          master∩worker={{ groups['master'] | default([]) | intersect(groups['worker'] | default([])) }},
          infra∩worker={{ groups['infra'] | default([]) | intersect(groups['worker'] | default([])) }}
        success_msg: "No host overlap across master/infra/worker groups"
        quiet: true
      run_once: true

    - name: Ensure required inventory variables are defined and not empty
      ansible.builtin.assert:
        that:
          - vars[item] is defined
          - vars[item] | string | trim | length > 0
        fail_msg: "'{{ item }}' is not defined or is empty in the inventory"
        success_msg: "'{{ item }}' is defined"
        quiet: true
      loop: "{{ required_vars }}"
      loop_control:
        label: "{{ item }}"
      run_once: true

    - name: Ensure cluster_name starts with 'k8s'
      ansible.builtin.assert:
        that:
          - cluster_name is match('^k8s')
        fail_msg: "cluster_name must start with 'k8s' (current: '{{ cluster_name }}')"
        success_msg: "cluster_name is valid"
        quiet: true
      run_once: true

    - name: Ensure env is one of the allowed values
      ansible.builtin.assert:
        that:
          - env in allowed_env
        fail_msg: "env must be one of {{ allowed_env }} (current: '{{ env }}')"
        success_msg: "env is valid"
        quiet: true
      run_once: true

    - name: Ensure cluster_env is one of the allowed values
      ansible.builtin.assert:
        that:
          - cluster_env in allowed_cluster_env
        fail_msg: "cluster_env must be one of {{ allowed_cluster_env }} (current: '{{ cluster_env }}')"
        success_msg: "cluster_env is valid"
        quiet: true
      run_once: true

    - name: Ensure env and cluster_env are consistent
      ansible.builtin.assert:
        that:
          - cluster_env == env_cluster_env_map[env]
        fail_msg: >-
          env/cluster_env mismatch → env='{{ env }}' expects
          cluster_env='{{ env_cluster_env_map[env] }}' but got '{{ cluster_env }}'
        success_msg: "env and cluster_env are consistent"
        quiet: true
      run_once: true

    - name: Ensure api_address matches the expected format
      ansible.builtin.assert:
        that:
          - api_address is match(api_address_regex)
        fail_msg: >-
          api_address must match 'api.{{ cluster_name }}.<string>.com:6443'
          (current: '{{ api_address }}')
        success_msg: "api_address format is valid"
        quiet: true
      run_once: true

    - name: Ensure pfx file name matches 'ingress-<cluster_name>.pfx'
      ansible.builtin.assert:
        that:
          - (pfx | basename) == expected_pfx_name
        fail_msg: >-
          pfx name must be '{{ expected_pfx_name }}' (current: '{{ pfx | basename }}')
        success_msg: "pfx name is valid"
        quiet: true
      run_once: true

    - name: Check that the pfx file exists on the local filesystem
      ansible.builtin.stat:
        path: "{{ expected_pfx_path }}"
      delegate_to: localhost
      run_once: true
      register: pfx_file

    - name: Ensure the pfx file is present under files/
      ansible.builtin.assert:
        that:
          - pfx_file.stat.exists
        fail_msg: "pfx file not found at '{{ expected_pfx_path }}'"
        success_msg: "pfx file found at '{{ expected_pfx_path }}'"
        quiet: true
      run_once: true

    # ------------------------------------------------------------------
    # Per-host checks - node must be clean (none of these files may exist)
    # Runs on every host except the 'hub' group
    # ------------------------------------------------------------------

    - name: Check kubelet.conf
      ansible.builtin.stat:
        path: /etc/kubernetes/kubelet.conf
      register: kubelet_conf

    - name: Check containerd config.toml
      ansible.builtin.stat:
        path: /etc/containerd/config.toml
      register: containerd_conf

    - name: Check kube-apiserver static pod manifest
      ansible.builtin.stat:
        path: /etc/kubernetes/manifests/kube-apiserver.yaml
      register: apiserver_manifest

    - name: Ensure node is clean (none of the 3 files must exist)
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
