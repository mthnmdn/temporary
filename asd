- hosts: new_workers
  gather_facts: false
  tasks:
    - name: Get FQDN from the target host
      ansible.builtin.command: hostname -f
      register: fqdn_result
      changed_when: false

    - name: Validate that FQDN matches inventory_hostname
      ansible.builtin.assert:
        that:
          - fqdn_result.stdout == inventory_hostname
        fail_msg: >-
          Mismatch! inventory_hostname='{{ inventory_hostname }}' but
          'hostname -f' returned '{{ fqdn_result.stdout }}'.
        success_msg: "FQDN match confirmed: {{ inventory_hostname }}"
