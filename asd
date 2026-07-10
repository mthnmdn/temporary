- name: Validate inventory variables
  hosts: all
  gather_facts: false
  tasks:
    - name: ansible_host tanımlı mı
      ansible.builtin.assert:
        that:
          - ansible_host is defined
        fail_msg: "{{ inventory_hostname }}: ansible_host tanımlanmamış"
        quiet: true

    - name: environment_name geçerli mi
      ansible.builtin.assert:
        that:
          - environment_name in ['dev', 'staging', 'prod']
        fail_msg: "{{ inventory_hostname }}: environment_name 'dev', 'staging' veya 'prod' olmalı (mevcut: {{ environment_name | default('tanımsız') }})"
        quiet: true

    - name: cluster_name boş değil mi
      ansible.builtin.assert:
        that:
          - cluster_name | length > 0
        fail_msg: "{{ inventory_hostname }}: cluster_name boş olamaz"
        quiet: true
