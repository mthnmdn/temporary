vars:
    # ... mevcut required_free_ports ...
    # Minimum worker kaynakları
    min_worker_cpu: 16          # core
    min_worker_memory_mb: 64000 # ~64 GB (bkz. aşağıdaki not)

  tasks:

    # ---- Kaynak kontrolü için sadece donanım fact'lerini topla ----
    - name: Gather hardware facts
      ansible.builtin.setup:
        gather_subset:
          - "!all"
          - "!min"
          - hardware

    # ---- Requirement 7: worker'lar minimum CPU/memory'ye sahip olmalı ----
    - name: Ensure worker meets minimum CPU and memory requirements
      ansible.builtin.assert:
        that:
          - ansible_processor_vcpus | int >= min_worker_cpu
          - ansible_memtotal_mb | int >= min_worker_memory_mb
        fail_msg: >-
          {{ inventory_hostname }}: insufficient resources -
          CPU: {{ ansible_processor_vcpus }} core (min {{ min_worker_cpu }}),
          Memory: {{ ansible_memtotal_mb }} MB (min {{ min_worker_memory_mb }} MB)
        success_msg: >-
          {{ inventory_hostname }}: resources OK
          ({{ ansible_processor_vcpus }} core / {{ ansible_memtotal_mb }} MB)
        quiet: true
